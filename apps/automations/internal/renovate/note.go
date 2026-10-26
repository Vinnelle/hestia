package renovate

import (
	"fmt"
	"strings"
)

const marker = "<!-- renovate-review -->"

const markdownPunctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"

func truncate(s string, n int) string {
	s = strings.Join(strings.Fields(s), " ")
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	return strings.TrimSpace(string(runes[:n])) + "…"
}

func escape(b *strings.Builder, s string) {
	for _, r := range s {
		if strings.ContainsRune(markdownPunctuation, r) {
			b.WriteRune('\\')
		}
		b.WriteRune(r)
		if r == '@' {
			b.WriteRune('​')
		}
	}
}

func inline(s string, n int) string {
	parts := strings.Split(truncate(s, n), "`")
	var b strings.Builder
	for i, part := range parts {
		switch {
		case i%2 == 0:
			escape(&b, part)
		case i < len(parts)-1:
			if part != "" {
				fmt.Fprintf(&b, "`%s`", part)
			}
		default:
			escape(&b, "`"+part)
		}
	}
	return b.String()
}

func codeSpan(s string, n int) string {
	s = truncate(strings.ReplaceAll(s, "`", ""), n)
	if s == "" {
		return ""
	}
	return "`" + s + "`"
}

func renderNote(a Assessment, sha, model string, accepted bool, label string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "%s\n**Renovate review: %s**\n\n", marker, a.Verdict)
	if summary := inline(a.Summary, 600); summary != "" {
		fmt.Fprintf(&b, "> %s\n\n", summary)
	}
	for _, f := range a.Findings {
		fmt.Fprintf(&b, "- **%s:** %s", f.Severity, inline(f.Detail, 400))
		if p := codeSpan(f.File, 200); p != "" {
			fmt.Fprintf(&b, " %s", p)
		}
		b.WriteString("\n")
	}
	if len(a.Findings) > 0 {
		b.WriteString("\n")
	}
	switch {
	case a.Verdict == Breaking && accepted:
		fmt.Fprintf(&b, "Accepted with the ~%q label, so the pipeline passes.\n\n", label)
	case a.Verdict == Breaking && label != "":
		fmt.Fprintf(&b, "The `renovate_review` job fails, so this will not automerge. To merge it anyway, add the ~%q label and retry the job.\n\n", label)
	}
	short := sha
	if len(short) > 8 {
		short = short[:8]
	}
	fmt.Fprintf(&b, "<sub>%s reviewed %s. A language model wrote this review, and it can be wrong.</sub>\n", codeSpan(model, 80), codeSpan(short, 8))
	return b.String()
}
