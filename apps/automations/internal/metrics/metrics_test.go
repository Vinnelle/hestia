package metrics

import (
	"io"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandlerWritesPrometheusText(t *testing.T) {
	verdicts := NewCounter("reviews_total", "Reviews by verdict", "verdict")
	verdicts.Add("safe", 2)
	verdicts.Add(`we"ird`, 1)
	last := NewGauge("last_seconds", "Last review", "")
	last.Set("", 1700000000)

	rec := httptest.NewRecorder()
	Handler(verdicts, last).ServeHTTP(rec, httptest.NewRequest("GET", "/metrics", nil))
	body, _ := io.ReadAll(rec.Body)
	want := "# HELP reviews_total Reviews by verdict\n# TYPE reviews_total counter\n" +
		"reviews_total{verdict=\"safe\"} 2\nreviews_total{verdict=\"we\\\"ird\"} 1\n" +
		"# HELP last_seconds Last review\n# TYPE last_seconds gauge\nlast_seconds 1.7e+09\n"
	if string(body) != want {
		t.Fatalf("body =\n%s\nwant\n%s", body, want)
	}
	if !strings.HasPrefix(rec.Header().Get("Content-Type"), "text/plain") {
		t.Fatalf("content type %q", rec.Header().Get("Content-Type"))
	}
}
