package main

import (
	"context"
	"errors"
	"html/template"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"vinnel-cloud-admin/internal/portal"
)

func TestAssetCache(t *testing.T) {
	cases := map[string]string{
		"/assets/js/theme.1a2b3c4d.js":   "public, max-age=31536000, immutable",
		"/assets/css/app.deadbeef.css":   "public, max-age=31536000, immutable",
		"/assets/fonts/jetbrains.woff2":  "public, max-age=2592000, immutable",
		"/assets/images/favicon.webp":    "public, max-age=2592000, immutable",
		"/assets/js/theme.js":            "no-cache",
		"/assets/css/style.notahash.css": "no-cache",
	}

	h := assetCache(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	for path, want := range cases {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		if got := w.Header().Get("Cache-Control"); got != want {
			t.Errorf("%s: Cache-Control = %q, want %q", path, got, want)
		}
	}
}

func TestRegistryIsConsistentWithCSP(t *testing.T) {
	seen := map[string]bool{}
	for _, s := range portal.Services {
		if s.Slug == "" || s.Label == "" || s.Host == "" {
			t.Errorf("service %+v is missing a required field", s)
		}
		if seen[s.Slug] {
			t.Errorf("duplicate slug %q — the hash router would show the wrong service", s.Slug)
		}
		seen[s.Slug] = true

		if !strings.HasSuffix(s.Host, ".vinnel.cloud") {
			t.Errorf("%s: host %q is outside vinnel.cloud; the frame would be cross-site, "+
				"so the app's cookies would not survive it", s.Slug, s.Host)
		}
		if s.Frameable && !strings.Contains(frameSrc, "https://"+s.Host) {
			t.Errorf("%s: frame-src is missing %q — our own CSP would blank the frame", s.Slug, s.Host)
		}
		if !s.Frameable && strings.Contains(frameSrc, "https://"+s.Host) {
			t.Errorf("%s: %q opens in a new tab and must not widen frame-src", s.Slug, s.Host)
		}
		if got := s.URL(); got != "https://"+s.Host+"/" {
			t.Errorf("%s: URL() = %q", s.Slug, got)
		}
	}

	if seen["dashboard"] {
		t.Error("dashboard.vinnel.cloud is deliberately out of scope for the portal")
	}
	if !strings.Contains(securityHeaders["Content-Security-Policy"], "frame-ancestors 'none'") {
		t.Error("the portal must not be frameable — it frames every service")
	}
}

func TestServicesHaveExactlyOneIconSource(t *testing.T) {
	for _, s := range portal.Services {
		if (s.IconURL == "") == (s.Icon == "") {
			t.Errorf("%s: exactly one of Icon (fallback) or IconURL (real logo) must be set, not both/neither", s.Slug)
		}
	}
}

func TestIndexTemplateRenders(t *testing.T) {
	tmpl := template.Must(template.ParseFS(htmlFS, "html/index.html"))
	data := pageData{User: "test@example.com", Services: portal.Services, ServiceGroups: portal.Groups()}
	if err := tmpl.Execute(io.Discard, data); err != nil {
		t.Fatalf("index.html failed to render: %v", err)
	}
}

func TestUserFromRequestPrefersEmail(t *testing.T) {
	r := httptest.NewRequest("GET", "/", nil)
	if got := userFromRequest(r); got != "" {
		t.Errorf("no Remote-* headers: got %q, want empty", got)
	}
	r.Header.Set("Remote-User", "ida")
	if got := userFromRequest(r); got != "ida" {
		t.Errorf("Remote-User only: got %q", got)
	}
	r.Header.Set("Remote-Email", "a@vin.moe")
	if got := userFromRequest(r); got != "a@vin.moe" {
		t.Errorf("Remote-Email set: got %q", got)
	}
}

func TestStreamHandlerFramesLinesAsSSE(t *testing.T) {
	srv := httptest.NewServer(streamHandler(func(ctx context.Context, lines int) (io.ReadCloser, error) {
		if lines != 12 {
			t.Errorf("lines = %d, want 12 (from the ?lines= query)", lines)
		}
		return io.NopCloser(strings.NewReader("first\r\nsecond\n")), nil
	}))
	defer srv.Close()

	resp, err := http.Get(srv.URL + "?lines=12")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Errorf("Content-Type = %q, want text/event-stream", ct)
	}
	if b := resp.Header.Get("X-Accel-Buffering"); b != "no" {
		t.Errorf("X-Accel-Buffering = %q, want no — nginx buffers the stream without it", b)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	if want := "data: first\n\ndata: second\n\n"; string(body) != want {
		t.Errorf("body = %q, want %q", body, want)
	}
}

func TestStreamHandlerReportsOpenFailure(t *testing.T) {
	srv := httptest.NewServer(streamHandler(func(context.Context, int) (io.ReadCloser, error) {
		return nil, errors.New("no pod matching \"app=minecraft\"")
	}))
	defer srv.Close()

	resp, err := http.Get(srv.URL)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadGateway {
		t.Errorf("status = %d, want %d", resp.StatusCode, http.StatusBadGateway)
	}
}
