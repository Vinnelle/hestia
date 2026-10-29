package tools

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

// TOR_SOCKS=127.0.0.1:9050 and SEARCH_URL=http://localhost:8080 run these
// against a real tor and SearXNG.

func TestProbeRead(t *testing.T) {
	socks := os.Getenv("TOR_SOCKS")
	if socks == "" {
		t.Skip()
	}
	r := TorReader(socks)
	for link, want := range map[string]string{
		"https://check.torproject.org/":     "Congratulations",
		"https://en.wikipedia.org/wiki/Fox": "fox",
		"https://chat.vin.moe/":             "chat",
	} {
		start := time.Now()
		got, err := r.Read(context.Background(), link, "")
		t.Logf("%s in %s: %v\n%.300s", link, time.Since(start).Round(time.Millisecond), err, got)
		if err == nil && !strings.Contains(strings.ToLower(got), strings.ToLower(want)) {
			t.Errorf("%s lacks %q", link, want)
		}
	}
	got, err := r.Read(context.Background(), "https://en.wikipedia.org/wiki/Fox", "arctic fox")
	t.Logf("find: %v\n%.600s", err, got)
}

func TestProbeSearch(t *testing.T) {
	base := os.Getenv("SEARCH_URL")
	if base == "" {
		t.Skip()
	}
	got, err := (&Searcher{BaseURL: base, HTTP: &http.Client{Timeout: time.Minute}}).Search(context.Background(), "red fox lifespan")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("\n%s", got)
}
