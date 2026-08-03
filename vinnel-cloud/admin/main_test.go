package main

import (
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
