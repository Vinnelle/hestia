package renovate

import (
	"strings"
	"testing"

	"automations/internal/gitlab"
)

func TestBuildPromptStaysNearTheBudget(t *testing.T) {
	mr := gitlab.MergeRequest{IID: 4, Title: "chore(deps): update loki", SourceBranch: "renovate/loki", TargetBranch: "pre", Description: strings.Repeat("n", 20000)}
	diffs := []gitlab.Diff{
		{OldPath: ".terraform.lock.hcl", NewPath: ".terraform.lock.hcl", Diff: "@@ -1 +1 @@\n-h1:old\n+h1:new"},
		{OldPath: "main.tf", NewPath: "main.tf", Diff: "@@ -1 +1 @@\n-a\n+b"},
	}
	files := []file{{Path: "big.yaml", Content: strings.Repeat("v", 20000)}, {Path: "late.yaml", Content: "x"}}
	got := buildPrompt(mr, diffs, files, 10000)

	if len(got) > 10600 {
		t.Fatalf("prompt is %d bytes for a 10000-byte budget", len(got))
	}
	if strings.Index(got, "+++ main.tf") > strings.Index(got, "+++ .terraform.lock.hcl") {
		t.Fatal("lockfile diff comes before the main.tf diff")
	}
	if !strings.Contains(got, "more bytes cut]") {
		t.Fatal("clipped sections are not marked")
	}
	if !strings.Contains(got, "Left out for length: late.yaml") {
		t.Fatalf("late.yaml is not reported as left out:\n%s", got[len(got)-200:])
	}
}

func TestClipKeepsRunesWhole(t *testing.T) {
	got := clip("ab€cd", 3)
	if !strings.HasPrefix(got, "ab\n[") {
		t.Fatalf("clip = %q, want the euro sign dropped whole", got)
	}
}
