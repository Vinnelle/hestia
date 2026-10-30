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

func TestProbeDocs(t *testing.T) {
	socks := os.Getenv("TOR_SOCKS")
	if socks == "" {
		t.Skip()
	}
	tag := os.Getenv("CHAT_TAG")
	if tag == "" {
		tag = "v0.5.4"
	}
	d := &Docs{Reader: TorReader(socks)}
	start := time.Now()
	n, err := d.Load(context.Background(), tag)
	t.Logf("loaded %d sections of %s in %s", n, tag, time.Since(start).Round(time.Millisecond))
	if err != nil {
		t.Fatal(err)
	}
	for _, q := range []string{"how do I make a private room", "verify codes", "tor bridges", "send a file", "what does :move do"} {
		got, err := d.Search(context.Background(), q)
		t.Logf("%q: %v\n%.800s", q, err, got)
		if err != nil || !strings.Contains(got, "<https://github.com/Vinnelle/chat/blob/"+tag+"/") {
			t.Errorf("%q found nothing", q)
		}
	}
}

func TestProbeManual(t *testing.T) {
	socks := os.Getenv("TOR_SOCKS")
	if socks == "" {
		t.Skip()
	}
	r := TorReader(socks)
	for _, c := range []struct{ page, find, want string }{
		{"rsync", "delete extraneous", "--delete"},
		{"sshd_config(5)", "PasswordAuthentication", "PasswordAuthentication"},
		{"docker-compose", "", "tldr docker-compose"},
		{"systemd.service", "Restart", "Restart="},
		{"ip", "route", "tldr ip"},
	} {
		start := time.Now()
		got, err := r.Manual(context.Background(), c.page, c.find)
		t.Logf("%s in %s: %v\n%.700s", c.page, time.Since(start).Round(time.Millisecond), err, got)
		if err != nil || !strings.Contains(got, c.want) {
			t.Errorf("%s lacks %q", c.page, c.want)
		}
	}
	if _, err := r.Manual(context.Background(), "nosuchthing123", ""); err == nil || !strings.Contains(err.Error(), "no tldr page or manual page") {
		t.Errorf("a missing page gave %v", err)
	}
}
