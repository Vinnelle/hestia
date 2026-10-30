package tools

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"path"
	"regexp"
	"slices"
	"sort"
	"strings"
	"sync"
	"unicode"
)

const (
	docsRaw      = "https://raw.githubusercontent.com/Vinnelle/chat/"
	docsBlob     = "https://github.com/Vinnelle/chat/blob/"
	docsIndex    = "docs/README.md"
	docsChars    = 4500
	sectionChars = 2500
	docsSections = 3
	maxDocs      = 24
)

type Docs struct {
	Reader *Reader

	loading  sync.Mutex
	mu       sync.RWMutex
	tag      string
	loaded   string
	sections []section
}

type section struct {
	file  string
	title string
	text  string
}

var docLink = regexp.MustCompile(`\]\(([A-Za-z0-9_./-]+\.md)\)`)

func (d *Docs) Load(ctx context.Context, tag string) (int, error) {
	d.loading.Lock()
	defer d.loading.Unlock()
	d.mu.Lock()
	d.tag = tag
	done, have := d.loaded == tag, len(d.sections)
	d.mu.Unlock()
	if done {
		return have, nil
	}
	index, err := d.fetch(ctx, tag, docsIndex)
	if err != nil {
		return 0, fmt.Errorf("%s: %w", docsIndex, err)
	}
	files := []string{"README.md", docsIndex}
	for _, m := range docLink.FindAllStringSubmatch(index, -1) {
		file := path.Clean(path.Join(path.Dir(docsIndex), m[1]))
		if strings.HasPrefix(file, "../") || strings.Contains(file, "..") || len(files) >= maxDocs || slices.Contains(files, file) {
			continue
		}
		files = append(files, file)
	}
	texts := make([]string, len(files))
	errs := make([]error, len(files))
	texts[1] = index
	var wg sync.WaitGroup
	for i, file := range files {
		if i == 1 {
			continue
		}
		wg.Go(func() { texts[i], errs[i] = d.fetch(ctx, tag, file) })
	}
	wg.Wait()
	var sections []section
	var failed []string
	for i, file := range files {
		if errs[i] != nil {
			failed = append(failed, file)
			continue
		}
		sections = append(sections, split(file, texts[i])...)
	}
	if len(failed) > len(files)/2 {
		return 0, fmt.Errorf("couldn't fetch %s: %w", strings.Join(failed, ", "), errors.Join(errs...))
	}
	d.mu.Lock()
	d.loaded, d.sections = tag, sections
	d.mu.Unlock()
	return len(sections), nil
}

func (d *Docs) fetch(ctx context.Context, tag, file string) (string, error) {
	u, err := url.Parse(docsRaw + url.PathEscape(tag) + "/" + file)
	if err != nil {
		return "", err
	}
	got, err := d.Reader.get(ctx, u, "text/plain,text/markdown;q=0.9,*/*;q=0.5")
	return got.body, err
}

func split(file, text string) []section {
	var out []section
	title, fenced := path.Base(file), false
	var body []string
	flush := func() {
		text := strings.TrimSpace(strings.Join(body, "\n"))
		body = nil
		for part, chunk := range chunks(text, sectionChars) {
			t := title
			if part > 0 {
				t += " (cont.)"
			}
			out = append(out, section{file: file, title: t, text: chunk})
		}
	}
	for line := range strings.SplitSeq(text, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "```") {
			fenced = !fenced
		}
		if hashes := len(line) - len(strings.TrimLeft(line, "#")); !fenced && hashes >= 1 && hashes <= 6 && strings.HasPrefix(line[hashes:], " ") {
			flush()
			title = strings.TrimSpace(line[hashes:])
			continue
		}
		body = append(body, line)
	}
	flush()
	return out
}

func chunks(text string, limit int) []string {
	if text == "" {
		return nil
	}
	var out []string
	var cur strings.Builder
	for para := range strings.SplitSeq(text, "\n\n") {
		if cur.Len() > 0 && cur.Len()+len(para)+2 > limit {
			out = append(out, cur.String())
			cur.Reset()
		}
		if cur.Len() > 0 {
			cur.WriteString("\n\n")
		}
		cur.WriteString(truncate(para, limit))
	}
	if cur.Len() > 0 {
		out = append(out, cur.String())
	}
	return out
}

func (d *Docs) Search(ctx context.Context, query string) (string, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return "", errors.New("the query is empty")
	}
	d.mu.RLock()
	tag, loaded := d.tag, d.loaded
	d.mu.RUnlock()
	if loaded == "" || loaded != tag {
		if tag == "" {
			return "", errors.New("chat's docs aren't loaded yet")
		}
		if _, err := d.Load(ctx, tag); err != nil && loaded == "" {
			return "", fmt.Errorf("couldn't load chat's docs: %w", err)
		}
	}
	d.mu.RLock()
	sections, tag := d.sections, d.loaded
	d.mu.RUnlock()

	words := slices.DeleteFunc(terms(query), func(w string) bool { return w == "chat" })
	if len(words) == 0 {
		return "", errors.New("the query needs a word to look for")
	}
	scores := make([]int, len(sections))
	order := make([]int, 0, len(sections))
	for i, s := range sections {
		if scores[i] = score(s.text, s.title, words); scores[i] > 0 {
			order = append(order, i)
		}
	}
	if len(order) == 0 {
		return fmt.Sprintf("nothing in chat's docs (%s) mentions %q", tag, query), nil
	}
	sort.SliceStable(order, func(a, b int) bool { return scores[order[a]] > scores[order[b]] })
	var b strings.Builder
	fmt.Fprintf(&b, "chat's docs at %s, best matches first:", tag)
	for _, i := range order[:min(len(order), docsSections)] {
		s := sections[i]
		head := fmt.Sprintf("\n\n%s, %q <%s%s/%s>\n", s.file, s.title, docsBlob, tag, s.file)
		if b.Len()+len(head)+200 > docsChars {
			break
		}
		b.WriteString(head)
		b.WriteString(truncate(s.text, docsChars-b.Len()))
	}
	return b.String(), nil
}

var stopWords = map[string]bool{
	"the": true, "and": true, "for": true, "how": true, "what": true, "does": true, "can": true, "you": true,
	"with": true, "are": true, "that": true, "this": true, "use": true, "into": true, "from": true, "about": true,
	"when": true, "why": true, "which": true, "there": true, "your": true, "its": true, "it's": true, "has": true,
	"have": true, "not": true, "but": true, "all": true, "any": true, "who": true, "where": true, "way": true,
}

func terms(query string) []string {
	var out []string
	seen := map[string]bool{}
	for _, w := range strings.FieldsFunc(strings.ToLower(query), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r) && !strings.ContainsRune(":-_.'", r)
	}) {
		w = strings.Trim(w, ".-'")
		if (len(w) < 3 && !strings.HasPrefix(w, ":")) || stopWords[w] {
			continue
		}
		if w = stem(w); !seen[w] {
			seen[w] = true
			out = append(out, w)
		}
	}
	return out
}

func stem(w string) string {
	for _, s := range []string{"ied", "ies", "ing", "ed", "es", "s"} {
		if strings.HasSuffix(w, s) && len(w)-len(s) >= 4 {
			return w[:len(w)-len(s)]
		}
	}
	return w
}

func score(text, title string, words []string) int {
	lower, head := strings.ToLower(text), strings.ToLower(title)
	s := 0
	for _, w := range words {
		n, inTitle := strings.Count(lower, w), strings.Contains(head, w)
		if n == 0 && !inTitle {
			continue
		}
		s += 10 + min(n, 5)
		if inTitle {
			s += 6
		}
	}
	return s
}
