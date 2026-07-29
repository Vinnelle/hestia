package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
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
