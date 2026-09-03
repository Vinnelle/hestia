package blog

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestMediaName(t *testing.T) {
	cases := []struct{ original, want string }{
		{"Screen Shot.PNG", "screen-shot-2cf24dba.png"},
		{"../../etc/passwd", "passwd-2cf24dba.bin"},
		{"no-extension", "no-extension-2cf24dba.bin"},
		{".hidden", "file-2cf24dba.hidden"},
		{"weird.name.tar.gz", "weirdnametar-2cf24dba.gz"},
	}
	for _, c := range cases {
		got := MediaName(c.original, []byte("hello"))
		if got != c.want {
			t.Errorf("MediaName(%q) = %q, want %q", c.original, got, c.want)
		}
		if !mediaNamePattern.MatchString(got) {
			t.Errorf("MediaName(%q) = %q, which is not a servable name", c.original, got)
		}
	}
}

func TestMediaSaveAndServe(t *testing.T) {
	m, err := NewMedia(t.TempDir())
	if err != nil {
		t.Fatalf("NewMedia: %v", err)
	}
	m.maxBytes = 64
	if _, err := m.Save("empty.png", nil); err == nil {
		t.Error("empty upload accepted")
	}
	if _, err := m.Save("big.png", make([]byte, int(m.maxBytes)+1)); err == nil {
		t.Error("oversized upload accepted")
	}

	name, err := m.SaveReader("Diagram.PNG", strings.NewReader("not really a png"))
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	again, err := m.Save("Diagram.PNG", []byte("not really a png"))
	if err != nil || again != name {
		t.Fatalf("second Save = %q, %v, want %q, nil", again, err, name)
	}

	w := httptest.NewRecorder()
	m.Serve(w, httptest.NewRequest(http.MethodGet, "/public/media/"+name, nil), name)
	if w.Code != http.StatusOK {
		t.Fatalf("Serve status = %d, want 200", w.Code)
	}
	if got := w.Header().Get("Content-Type"); got != "image/png" {
		t.Errorf("Content-Type = %q, want image/png", got)
	}
	if w.Body.String() != "not really a png" {
		t.Errorf("body = %q", w.Body.String())
	}

	script, err := m.Save("payload.svg", []byte("<svg onload='alert(1)'></svg>"))
	if err != nil {
		t.Fatalf("Save: %v", err)
	}
	w = httptest.NewRecorder()
	m.Serve(w, httptest.NewRequest(http.MethodGet, "/public/media/"+script, nil), script)
	if got := w.Header().Get("Content-Type"); got != "application/octet-stream" {
		t.Errorf("svg Content-Type = %q, want application/octet-stream", got)
	}
	if !strings.HasPrefix(w.Header().Get("Content-Disposition"), "attachment") {
		t.Error("svg served inline, want attachment")
	}

	for _, bad := range []string{"../secret.png", "a/b.png", "Upload.PNG", "no-extension", ""} {
		w := httptest.NewRecorder()
		m.Serve(w, httptest.NewRequest(http.MethodGet, "/public/media/x", nil), bad)
		if w.Code != http.StatusNotFound {
			t.Errorf("Serve(%q) status = %d, want 404", bad, w.Code)
		}
	}
}
