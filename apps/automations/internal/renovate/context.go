package renovate

import (
	"context"
	"errors"
	"fmt"
	"path"
	"regexp"
	"strconv"
	"strings"

	"automations/internal/gitlab"
)

const (
	contextRadius   = 30
	referenceRadius = 10
	maxReferences   = 8
)

var lockFiles = []string{".terraform.lock.hcl", "go.sum", "package-lock.json"}

var hunkHeader = regexp.MustCompile(`^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@`)

var moduleRef = regexp.MustCompile(`\$\{path\.module\}/([A-Za-z0-9_./-]+)`)

var blockStart = regexp.MustCompile(`^[a-z_]+( "[^"]*")* \{\s*$`)

type file struct {
	Path    string
	Content string
}

func isLockFile(p string) bool {
	for _, name := range lockFiles {
		if path.Base(p) == name {
			return true
		}
	}
	return false
}

func changedLines(diff string) []int {
	var lines []int
	n := 0
	for l := range strings.SplitSeq(diff, "\n") {
		if m := hunkHeader.FindStringSubmatch(l); m != nil {
			n, _ = strconv.Atoi(m[1])
			continue
		}
		if n == 0 {
			continue
		}
		switch {
		case strings.HasPrefix(l, "+"):
			lines = append(lines, n)
			n++
		case strings.HasPrefix(l, "-"):
			lines = append(lines, n)
		case strings.HasPrefix(l, `\`):
		default:
			n++
		}
	}
	return lines
}

func near(line int, around []int, radius int) bool {
	for _, n := range around {
		if line >= n-radius && line <= n+radius {
			return true
		}
	}
	return false
}

func enclosingBlock(lines []string, n int) (int, int, bool) {
	start := 0
	for i := min(n, len(lines)); i >= 1; i-- {
		if blockStart.MatchString(lines[i-1]) {
			start = i
			break
		}
		if i < n && strings.TrimRight(lines[i-1], " \t") == "}" {
			return 0, 0, false
		}
	}
	if start == 0 {
		return 0, 0, false
	}
	for j := start + 1; j <= len(lines); j++ {
		if strings.TrimRight(lines[j-1], " \t") == "}" {
			return start, j, true
		}
	}
	return 0, 0, false
}

func related(lines []string, line int, around []int) bool {
	for _, n := range around {
		if start, end, ok := enclosingBlock(lines, n); ok {
			if line >= start && line <= end {
				return true
			}
		} else if near(line, []int{n}, referenceRadius) {
			return true
		}
	}
	return false
}

func excerpt(content string, around []int, radius int) string {
	lines := strings.Split(content, "\n")
	if len(around) == 0 {
		return content
	}
	keep := make([]bool, len(lines))
	for _, n := range around {
		for i := max(n-1-radius, 0); i <= min(n-1+radius, len(lines)-1); i++ {
			keep[i] = true
		}
	}
	var b strings.Builder
	for i := 0; i < len(lines); {
		if !keep[i] {
			i++
			continue
		}
		j := i
		for j < len(lines) && keep[j] {
			j++
		}
		fmt.Fprintf(&b, "[lines %d-%d]\n%s\n", i+1, j, strings.Join(lines[i:j], "\n"))
		i = j
	}
	return strings.TrimRight(b.String(), "\n")
}

func references(from, content string, around []int) []string {
	lines := strings.Split(content, "\n")
	var out []string
	for _, loc := range moduleRef.FindAllStringSubmatchIndex(content, -1) {
		line := strings.Count(content[:loc[0]], "\n") + 1
		if !related(lines, line, around) {
			continue
		}
		p := path.Clean(path.Join(path.Dir(from), content[loc[2]:loc[3]]))
		if p == "." || p == ".." || strings.HasPrefix(p, "../") || path.Ext(p) == "" {
			continue
		}
		out = append(out, p)
	}
	return out
}

func (r *Reviewer) contextFiles(ctx context.Context, sha string, diffs []gitlab.Diff) ([]file, error) {
	fetch := func(p string) (string, bool, error) {
		data, err := r.GitLab.File(ctx, p, sha)
		if errors.Is(err, gitlab.ErrNotFound) {
			return "", false, nil
		}
		if err != nil {
			return "", false, err
		}
		return string(data), true, nil
	}

	seen := map[string]bool{}
	var changed, referenced []file
	for _, d := range diffs {
		if d.DeletedFile || isLockFile(d.NewPath) || seen[d.NewPath] {
			continue
		}
		seen[d.NewPath] = true
		content, ok, err := fetch(d.NewPath)
		if err != nil {
			return nil, err
		}
		if !ok {
			continue
		}
		around := changedLines(d.Diff)
		changed = append(changed, file{Path: d.NewPath, Content: excerpt(content, around, contextRadius)})
		if !strings.HasSuffix(d.NewPath, ".tf") {
			continue
		}
		for _, ref := range references(d.NewPath, content, around) {
			if seen[ref] || len(referenced) >= maxReferences {
				continue
			}
			seen[ref] = true
			body, ok, err := fetch(ref)
			if err != nil {
				return nil, err
			}
			if ok {
				referenced = append(referenced, file{Path: ref, Content: body})
			}
		}
	}
	return append(changed, referenced...), nil
}
