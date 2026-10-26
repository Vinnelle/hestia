package renovate

import (
	"strings"
	"testing"
)

func TestRenderNoteNeutralisesModelText(t *testing.T) {
	a := Assessment{
		Verdict: Breaking,
		Summary: "Fine.\n/merge\n@all see ![x](https://tracker.example/p.png) <img src=x>",
		Findings: []Finding{
			{Severity: "breaking", Detail: "line one\n/approve\n[link](https://evil.example)", File: "a`b.tf\n/close"},
		},
	}
	note := renderNote(a, "0123456789abcdef", "qwen", false, "review-accepted")

	if !strings.HasPrefix(note, marker+"\n") {
		t.Fatalf("note does not start with the marker:\n%s", note)
	}
	for line := range strings.SplitSeq(note, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "/") {
			t.Fatalf("line could run a quick action: %q", line)
		}
	}
	for _, raw := range []string{"@all", "![x]", "](https", " <img", "[link]"} {
		if strings.Contains(note, raw) {
			t.Fatalf("note keeps %q unescaped:\n%s", raw, note)
		}
	}
	if !strings.Contains(note, "`ab.tf /close`") {
		t.Fatalf("file is not a single-line code span:\n%s", note)
	}
	if !strings.Contains(note, `~"review-accepted" label and retry`) || !strings.Contains(note, "`01234567`") {
		t.Fatalf("note lacks the override hint or the short SHA:\n%s", note)
	}
}

func TestRenderNoteSaysWhenALabelAcceptedIt(t *testing.T) {
	note := renderNote(Assessment{Verdict: Breaking}, "abc", "qwen", true, "review-accepted")
	if !strings.Contains(note, "Accepted with the ~\"review-accepted\" label") || strings.Contains(note, "retry the job") {
		t.Fatalf("note = %s", note)
	}
}

func TestInlineKeepsBalancedCodeSpans(t *testing.T) {
	got := inline("rename `a.b` to `c <img> @all`, then `x", 200)
	want := "rename `a.b` to `c <img> @all`\\, then \\`x"
	if got != want {
		t.Fatalf("inline = %q, want %q", got, want)
	}
}

func TestInlineTruncatesByRune(t *testing.T) {
	if got := inline("ééééé", 3); got != "ééé…" {
		t.Fatalf("inline = %q", got)
	}
}
