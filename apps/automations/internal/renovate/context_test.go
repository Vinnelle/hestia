package renovate

import (
	"slices"
	"strings"
	"testing"
)

const helmDiff = `@@ -59,7 +59,7 @@ resource "helm_release" "loki" {
   repository = "https://grafana.github.io/helm-charts"
   chart      = "loki"
-  version    = "7.5.0"
+  version    = "7.6.0"
   namespace  = local.namespace
   timeout    = 600

@@ -120,3 +120,4 @@ resource "helm_release" "otel_collector" {
 a
+b
 c
\ No newline at end of file`

func TestChangedLinesFollowsHunkHeaders(t *testing.T) {
	got := changedLines(helmDiff)
	want := []int{61, 61, 121}
	if !slices.Equal(got, want) {
		t.Fatalf("changedLines = %v, want %v", got, want)
	}
}

func TestReferencesNearAChangeResolveFromTheModule(t *testing.T) {
	content := strings.Repeat("\n", 64) +
		"  values = [file(\"${path.module}/../../platform/helm-values/loki/values.yaml\")]\n" +
		"  escape = file(\"${path.module}/../../../../etc/passwd\")\n" +
		"  dir    = \"${path.module}/talos\"\n" +
		strings.Repeat("\n", 100) +
		"  far = file(\"${path.module}/far.yaml\")\n"
	got := references("hestia/observability/grafana/main.tf", content, []int{61})
	want := []string{"hestia/platform/helm-values/loki/values.yaml"}
	if !slices.Equal(got, want) {
		t.Fatalf("references = %v, want %v", got, want)
	}
}

func TestReferencesStayInTheChangedBlock(t *testing.T) {
	content := strings.Join([]string{
		`resource "helm_release" "victoria_metrics" {`,
		`  values = [file("${path.module}/vm.yaml")]`,
		`}`,
		``,
		`resource "helm_release" "loki" {`,
		`  chart   = "loki"`,
		`  version = "7.6.0"`,
		`  set {`,
		`    name = "a"`,
		`  }`,
		``, ``, ``, ``, ``, ``, ``, ``,
		`  values = [file("${path.module}/loki.yaml")]`,
		`}`,
		`resource "helm_release" "otel" {`,
		`  values = [file("${path.module}/otel.yaml")]`,
		`}`,
	}, "\n")
	got := references("main.tf", content, []int{7})
	if !slices.Equal(got, []string{"loki.yaml"}) {
		t.Fatalf("references = %v, want only loki.yaml", got)
	}
}

func TestExcerptKeepsWindowsAroundChanges(t *testing.T) {
	var lines []string
	for i := 1; i <= 100; i++ {
		lines = append(lines, "line")
	}
	got := excerpt(strings.Join(lines, "\n"), []int{10, 90}, 2)
	if !strings.HasPrefix(got, "[lines 8-12]\n") || !strings.Contains(got, "[lines 88-92]\n") || strings.Count(got, "line\n")+1 < 10 {
		t.Fatalf("excerpt = %q", got)
	}
	if strings.Count(got, "[lines") != 2 {
		t.Fatalf("excerpt has %d windows, want 2", strings.Count(got, "[lines"))
	}
}
