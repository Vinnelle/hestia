package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"html/template"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"vinnel-cloud-admin/internal/blog"
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
	if !strings.Contains(contentSecurityPolicy(""), "frame-ancestors 'none'") {
		t.Error("the portal must not be frameable — it frames every service")
	}
}

func TestContentSecurityPolicyCarriesNonce(t *testing.T) {
	policy := contentSecurityPolicy("abc123")
	if !strings.Contains(policy, "style-src 'self' 'nonce-abc123'") {
		t.Errorf("the editor's runtime styles need the nonce: %s", policy)
	}

	if bare := contentSecurityPolicy(""); strings.Contains(bare, "nonce-") {
		t.Errorf("an empty nonce must not widen the policy: %s", bare)
	}

	if got := originOf("https://blog.vin.moe/media"); got != "https://blog.vin.moe" {
		t.Errorf("originOf = %q", got)
	}
	if got := originOf(""); got != "" {
		t.Errorf("originOf of an empty URL = %q", got)
	}

	if a, b := newNonce(), newNonce(); a == b || a == "" {
		t.Errorf("nonces must be unique and non-empty: %q %q", a, b)
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

func blogTestAPI(t *testing.T, repo *blog.Repo) (*blogAPI, *http.ServeMux) {
	t.Helper()
	store, err := blog.NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	media, err := blog.NewMedia(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	api := &blogAPI{store: store, media: media, repo: repo, publicURL: "https://blog.vin.moe"}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/blog/posts", api.list)
	mux.HandleFunc("GET /api/blog/slug", api.slugify)
	mux.HandleFunc("GET /api/blog/posts/{slug}", api.get)
	mux.HandleFunc("PUT /api/blog/posts/{slug}", api.save)
	mux.HandleFunc("DELETE /api/blog/posts/{slug}", api.remove)
	mux.HandleFunc("POST /api/blog/posts/{slug}/publish", api.publish)
	mux.HandleFunc("POST /api/blog/posts/{slug}/unpublish", api.unpublish)
	mux.HandleFunc("POST /api/blog/media", api.upload)
	mux.HandleFunc("GET /public/media/{name}", api.publicMedia)
	return api, mux
}

func blogDo(t *testing.T, mux *http.ServeMux, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r *http.Request
	if body == "" {
		r = httptest.NewRequest(method, path, nil)
	} else {
		r = httptest.NewRequest(method, path, strings.NewReader(body))
	}
	r.Header.Set("Remote-Email", "a@vin.moe")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, r)
	return w
}

func TestBlogSaveAndGet(t *testing.T) {
	_, mux := blogTestAPI(t, &blog.Repo{})

	w := blogDo(t, mux, "PUT", "/api/blog/posts/first-post", `{"title":"First","date":"2026-08-21","body":"hello","draft":true}`)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT = %d, body %s", w.Code, w.Body)
	}

	w = blogDo(t, mux, "GET", "/api/blog/posts/first-post", "")
	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"title":"First"`) {
		t.Fatalf("GET = %d, body %s", w.Code, w.Body)
	}

	w = blogDo(t, mux, "GET", "/api/blog/posts", "")
	if !strings.Contains(w.Body.String(), `"publishing":false`) {
		t.Errorf("list should report publishing disabled: %s", w.Body)
	}
}

func TestBlogSaveDefaultsDate(t *testing.T) {
	_, mux := blogTestAPI(t, &blog.Repo{})
	w := blogDo(t, mux, "PUT", "/api/blog/posts/dated", `{"title":"No date","body":"x"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT = %d, body %s", w.Code, w.Body)
	}
	want := time.Now().UTC().Format("2006-01-02")
	if !strings.Contains(w.Body.String(), want) {
		t.Errorf("saved post did not default date to %s: %s", want, w.Body)
	}
}

func TestBlogRejectsBadInput(t *testing.T) {
	_, mux := blogTestAPI(t, &blog.Repo{})

	cases := map[string]struct {
		path, body string
		want       int
	}{
		"traversal slug": {"/api/blog/posts/..%2Fescape", `{"title":"T","date":"2026-08-21"}`, http.StatusBadRequest},
		"empty title":    {"/api/blog/posts/ok", `{"title":"","date":"2026-08-21"}`, http.StatusBadRequest},
		"bad date":       {"/api/blog/posts/ok", `{"title":"T","date":"nope"}`, http.StatusBadRequest},
		"malformed json": {"/api/blog/posts/ok", `{`, http.StatusBadRequest},
	}
	for name, c := range cases {
		if w := blogDo(t, mux, "PUT", c.path, c.body); w.Code != c.want {
			t.Errorf("%s: status = %d, want %d (%s)", name, w.Code, c.want, w.Body)
		}
	}

	if w := blogDo(t, mux, "GET", "/api/blog/posts/missing", ""); w.Code != http.StatusNotFound {
		t.Errorf("GET missing = %d, want 404", w.Code)
	}
}

func TestBlogPublishFlipsDraftWithoutImmediateSync(t *testing.T) {
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusForbidden)
	}))
	defer srv.Close()

	repo := &blog.Repo{BaseURL: srv.URL, ProjectID: "p", Token: "t", Branch: "pre", PostsPath: "posts", Client: srv.Client()}
	_, mux := blogTestAPI(t, repo)

	blogDo(t, mux, "PUT", "/api/blog/posts/live", `{"title":"Live","date":"2026-08-21","body":"x","draft":true}`)

	if w := blogDo(t, mux, "POST", "/api/blog/posts/live/publish", ""); w.Code != http.StatusOK {
		t.Fatalf("publish = %d, body %s", w.Code, w.Body)
	}
	if requests != 0 {
		t.Errorf("repository requests = %d, want 0", requests)
	}

	w := blogDo(t, mux, "GET", "/api/blog/posts/live", "")
	if !strings.Contains(w.Body.String(), `"draft":false`) {
		t.Errorf("publish did not clear the draft flag: %s", w.Body)
	}
}

func TestBlogPublishDoesNotContactRepository(t *testing.T) {
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusForbidden)
	}))
	defer srv.Close()

	repo := &blog.Repo{BaseURL: srv.URL, ProjectID: "p", Token: "t", Branch: "pre", PostsPath: "posts", Client: srv.Client()}
	_, mux := blogTestAPI(t, repo)

	blogDo(t, mux, "PUT", "/api/blog/posts/stuck", `{"title":"Stuck","date":"2026-08-21","draft":true}`)
	if w := blogDo(t, mux, "POST", "/api/blog/posts/stuck/publish", ""); w.Code != http.StatusOK {
		t.Fatalf("publish = %d, want 200", w.Code)
	}
	w := blogDo(t, mux, "GET", "/api/blog/posts/stuck", "")
	if !strings.Contains(w.Body.String(), `"draft":false`) {
		t.Errorf("publish did not clear the draft flag: %s", w.Body)
	}
	if requests != 0 {
		t.Errorf("repository requests = %d, want 0", requests)
	}
}

func TestBlogSlugifyDeduplicates(t *testing.T) {
	_, mux := blogTestAPI(t, &blog.Repo{})

	w := blogDo(t, mux, "GET", "/api/blog/slug?title=Hello+World", "")
	if !strings.Contains(w.Body.String(), `"slug":"hello-world"`) {
		t.Fatalf("slug = %s", w.Body)
	}

	blogDo(t, mux, "PUT", "/api/blog/posts/hello-world", `{"title":"Hello World","date":"2026-08-21"}`)
	w = blogDo(t, mux, "GET", "/api/blog/slug?title=Hello+World", "")
	if !strings.Contains(w.Body.String(), `"slug":"hello-world-2"`) {
		t.Errorf("second slug = %s, want hello-world-2", w.Body)
	}

	w = blogDo(t, mux, "GET", "/api/blog/slug?title=%21%21%21", "")
	if !strings.Contains(w.Body.String(), `"slug":"post"`) {
		t.Errorf("unsluggable title = %s, want post", w.Body)
	}
}

func TestBlogDeleteLeavesRepoForNightlySync(t *testing.T) {
	requests := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusForbidden)
	}))
	defer srv.Close()

	repo := &blog.Repo{BaseURL: srv.URL, ProjectID: "p", Token: "t", Branch: "pre", PostsPath: "posts", Client: srv.Client()}
	api, mux := blogTestAPI(t, repo)

	blogDo(t, mux, "PUT", "/api/blog/posts/bye", `{"title":"Bye","date":"2026-08-21"}`)
	if w := blogDo(t, mux, "DELETE", "/api/blog/posts/bye", ""); w.Code != http.StatusOK {
		t.Fatalf("delete = %d, body %s", w.Code, w.Body)
	}
	if requests != 0 {
		t.Errorf("repository requests = %d, want 0", requests)
	}
	if api.store.Exists("bye") {
		t.Error("post still on disk after delete")
	}
}

func TestPublicPostPage(t *testing.T) {
	api, mux := blogTestAPI(t, &blog.Repo{})
	api.feed = blog.FeedConfig{Title: "vin.moe", SiteURL: "https://vin.moe", PostLinkBase: "https://blog.vin.moe/posts/", Author: "Finlay"}
	mux.HandleFunc("GET /public/posts/{slug}", api.publicPost)

	blogDo(t, mux, "PUT", "/api/blog/posts/live-post", `{"title":"Live","date":"2026-08-21","body":"hello page","draft":false}`)
	blogDo(t, mux, "PUT", "/api/blog/posts/draft-post", `{"title":"Draft","date":"2026-08-21","body":"secret","draft":true}`)

	w := blogDo(t, mux, "GET", "/public/posts/live-post", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET = %d, body %s", w.Code, w.Body)
	}
	if ct := w.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Errorf("Content-Type = %q", ct)
	}
	for _, want := range []string{"hello page", `href="https://blog.vin.moe/posts/live-post"`} {
		if !strings.Contains(w.Body.String(), want) {
			t.Errorf("page missing %q", want)
		}
	}

	if w := blogDo(t, mux, "GET", "/public/posts/draft-post", ""); w.Code != http.StatusNotFound {
		t.Errorf("draft page = %d, want %d", w.Code, http.StatusNotFound)
	}
	if w := blogDo(t, mux, "GET", "/public/posts/missing", ""); w.Code != http.StatusNotFound {
		t.Errorf("missing page = %d, want %d", w.Code, http.StatusNotFound)
	}
}

func TestPublicPostsRevalidatesWithETag(t *testing.T) {
	api, mux := blogTestAPI(t, &blog.Repo{})
	mux.HandleFunc("GET /public/posts.json", api.publicPosts)

	blogDo(t, mux, "PUT", "/api/blog/posts/live-post", `{"title":"Live","date":"2026-08-21","body":"hello","draft":false}`)

	w := blogDo(t, mux, "GET", "/public/posts.json", "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET = %d, body %s", w.Code, w.Body)
	}
	etag := w.Header().Get("ETag")
	if etag == "" {
		t.Fatal("public posts served without an ETag")
	}
	if cc := w.Header().Get("Cache-Control"); !strings.Contains(cc, "must-revalidate") || !strings.Contains(cc, "s-maxage=") {
		t.Errorf("Cache-Control = %q", cc)
	}

	conditional := func() *httptest.ResponseRecorder {
		r := httptest.NewRequest("GET", "/public/posts.json", nil)
		r.Header.Set("If-None-Match", etag)
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, r)
		return rec
	}

	if got := conditional().Code; got != http.StatusNotModified {
		t.Errorf("unchanged posts = %d, want %d", got, http.StatusNotModified)
	}

	blogDo(t, mux, "PUT", "/api/blog/posts/live-post", `{"title":"Live","date":"2026-08-21","body":"hello again","draft":false}`)

	if got := conditional().Code; got != http.StatusOK {
		t.Errorf("edited posts = %d, want %d", got, http.StatusOK)
	}
}

func TestBlogUploadStoresAndServesMedia(t *testing.T) {
	_, mux := blogTestAPI(t, &blog.Repo{})

	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	part, err := form.CreateFormFile("file", "Holiday Photo.JPG")
	if err != nil {
		t.Fatal(err)
	}
	part.Write([]byte("jpeg bytes"))
	form.Close()

	r := httptest.NewRequest("POST", "/api/blog/media", &body)
	r.Header.Set("Content-Type", form.FormDataContentType())
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("upload = %d, body %s", w.Code, w.Body)
	}

	var uploaded struct{ Name, URL string }
	if err := json.Unmarshal(w.Body.Bytes(), &uploaded); err != nil {
		t.Fatal(err)
	}
	if want := "https://blog.vin.moe/media/" + uploaded.Name; uploaded.URL != want {
		t.Errorf("url = %q, want %q", uploaded.URL, want)
	}

	w = blogDo(t, mux, "GET", "/public/media/"+uploaded.Name, "")
	if w.Code != http.StatusOK || w.Body.String() != "jpeg bytes" {
		t.Fatalf("serve = %d, body %q", w.Code, w.Body)
	}
	if got := w.Header().Get("Content-Type"); got != "image/jpeg" {
		t.Errorf("Content-Type = %q, want image/jpeg", got)
	}

	w = blogDo(t, mux, "GET", "/public/media/missing-00000000.png", "")
	if w.Code != http.StatusNotFound {
		t.Errorf("missing media = %d, want 404", w.Code)
	}
}

func TestBlogUploadRejectsEmptyRequest(t *testing.T) {
	_, mux := blogTestAPI(t, &blog.Repo{})

	r := httptest.NewRequest("POST", "/api/blog/media", strings.NewReader(""))
	r.Header.Set("Content-Type", "multipart/form-data; boundary=none")
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, r)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("upload without a file = %d, want 400", w.Code)
	}
}

func TestPurgeTargetsCoverEveryCachedHost(t *testing.T) {
	got := purgeTargets("https://vin.moe/", "https://blog.vin.moe")
	want := []string{
		"https://vin.moe/", "https://vin.moe/posts.json", "https://vin.moe/feed.xml", "https://vin.moe/sitemap.xml",
		"https://blog.vin.moe/", "https://blog.vin.moe/posts.json", "https://blog.vin.moe/feed.xml", "https://blog.vin.moe/sitemap.xml",
	}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("purgeTargets = %q, want %q", got, want)
	}
	if got := purgeTargets("https://vin.moe", ""); len(got) != 4 {
		t.Fatalf("no public host: got %q", got)
	}
}
