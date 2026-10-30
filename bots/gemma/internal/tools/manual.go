package tools

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"sync"
)

const (
	tldrRaw     = "https://raw.githubusercontent.com/tldr-pages/tldr/main/pages/"
	manPages    = "https://man.archlinux.org/man/"
	maxPageName = 64
	tldrChars   = 1500
	manChars    = 3000
)

var (
	pageName = regexp.MustCompile(`^([A-Za-z0-9_][A-Za-z0-9_.+-]*?)(?:\(([0-9][a-z]*)\)|\.([0-9][a-z]*))?$`)
	manFinal = regexp.MustCompile(`/man/([^/]+)\.([0-9][a-z]*)\.txt$`)
)

func (r *Reader) Manual(ctx context.Context, name, find string) (string, error) {
	name = strings.Join(strings.Fields(name), "-")
	m := pageName.FindStringSubmatch(name)
	if len(name) > maxPageName || m == nil {
		return "", errors.New("give the name of one command, config file or function, like rsync, sshd_config or systemd.service")
	}
	page, sect := m[1], m[2]+m[3]
	var tldr, man string
	var tldrErr, manErr error
	var wg sync.WaitGroup
	wg.Go(func() { tldr, tldrErr = r.tldr(ctx, strings.ToLower(page)) })
	wg.Go(func() { man, manErr = r.man(ctx, page, sect, find) })
	wg.Wait()
	if tldr == "" && man == "" {
		if notFound(tldrErr) && notFound(manErr) {
			return "", fmt.Errorf("there's no tldr page or manual page called %s; search for it instead", name)
		}
		return "", errors.Join(tldrErr, manErr)
	}
	var b strings.Builder
	if tldr != "" {
		b.WriteString(tldr)
	}
	if man != "" {
		if b.Len() > 0 {
			b.WriteString("\n\n")
		}
		b.WriteString(man)
	}
	return b.String(), nil
}

func (r *Reader) tldr(ctx context.Context, page string) (string, error) {
	var err error
	for _, platform := range []string{"common", "linux"} {
		u, _ := url.Parse(tldrRaw + platform + "/" + url.PathEscape(page) + ".md")
		var got fetched
		if got, err = r.get(ctx, u, "text/plain,*/*;q=0.5"); err == nil {
			return "tldr " + page + " (tldr-pages, CC BY 4.0):\n" + truncate(tldrText(got.body), tldrChars), nil
		}
		if !notFound(err) {
			break
		}
	}
	return "", err
}

func tldrText(md string) string {
	var lines []string
	example := ""
	for line := range strings.SplitSeq(md, "\n") {
		line = strings.ReplaceAll(strings.ReplaceAll(strings.TrimSpace(line), "{{", ""), "}}", "")
		switch {
		case line == "" || strings.HasPrefix(line, "# "):
		case strings.HasPrefix(line, "> "):
			lines = append(lines, strings.TrimPrefix(line, "> "))
		case strings.HasPrefix(line, "- "):
			example = strings.TrimSuffix(strings.TrimPrefix(line, "- "), ":")
		case strings.HasPrefix(line, "`") && strings.HasSuffix(line, "`") && len(line) > 1:
			lines = append(lines, "- "+example+": "+strings.Trim(line, "`"))
			example = ""
		}
	}
	return strings.Join(lines, "\n")
}

func (r *Reader) man(ctx context.Context, page, sect, find string) (string, error) {
	name := page
	if sect != "" {
		name += "." + sect
	}
	u, _ := url.Parse(manPages + url.PathEscape(name) + ".txt")
	got, err := r.get(ctx, u, "text/plain,*/*;q=0.5")
	if err != nil {
		return "", err
	}
	title := page
	if m := manFinal.FindStringSubmatch(got.final); m != nil {
		title = m[1] + "(" + m[2] + ")"
	}
	link := strings.TrimSuffix(got.final, ".txt")
	return fmt.Sprintf("man page %s <%s>:\n%s", title, link, passages(manText(got.body), find, manChars)), nil
}

func manText(text string) string {
	var lines []string
	for line := range strings.SplitSeq(text, "\n") {
		lines = append(lines, strings.Join(strings.Fields(line), " "))
	}
	return strings.TrimSpace(strings.Join(lines, "\n"))
}

func passages(text, find string, limit int) string {
	words := terms(find)
	paras := strings.Split(text, "\n\n")
	if len(words) == 0 {
		return truncate(text, limit)
	}
	scores := make([]int, len(paras))
	order := make([]int, 0, len(paras))
	for i, p := range paras {
		if scores[i] = score(p, "", words); scores[i] > 0 {
			order = append(order, i)
		}
	}
	if len(order) == 0 {
		return truncate("(nothing in it mentions "+find+"; it starts:)\n"+text, limit/2)
	}
	sort.SliceStable(order, func(a, b int) bool { return scores[order[a]] > scores[order[b]] })
	taken := map[int]bool{}
	size := 0
	for _, i := range order {
		if size >= limit {
			break
		}
		taken[i] = true
		size += len(paras[i]) + 2
	}
	var picked []string
	for i, p := range paras {
		if taken[i] {
			picked = append(picked, p)
		}
	}
	return truncate(strings.Join(picked, "\n\n"), limit)
}
