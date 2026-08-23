package blog

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"encoding/xml"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestValidSlug(t *testing.T) {
	good := []string{"a", "hello", "hello-world", "post-2026-08-21", "a1-b2"}
	for _, s := range good {
		if !ValidSlug(s) {
			t.Errorf("ValidSlug(%q) = false, want true", s)
		}
	}
	bad := []string{"", "..", "../etc/passwd", "a/b", "Hello", "trailing-", "-leading", "double--dash", "has space", strings.Repeat("a", MaxSlug+1)}
	for _, s := range bad {
		if ValidSlug(s) {
			t.Errorf("ValidSlug(%q) = true, want false", s)
		}
	}
}

func TestSlugify(t *testing.T) {
	cases := map[string]string{
		"Hello World":                   "hello-world",
		"  Trim  Me  ":                  "trim-me",
		"Your Talos installer, part 2!": "your-talos-installer-part-2",
		"---":                           "",
		"a/b_c d":                       "a-b-c-d",
		strings.Repeat("long ", 40):     strings.Trim(strings.Repeat("long-", 16)[:MaxSlug], "-"),
	}
	for in, want := range cases {
		if got := Slugify(in); got != want {
			t.Errorf("Slugify(%q) = %q, want %q", in, got, want)
		}
	}
	if got := Slugify(strings.Repeat("a", 200)); len(got) > MaxSlug {
		t.Errorf("Slugify produced %d chars, over MaxSlug %d", len(got), MaxSlug)
	}
}

func TestValidate(t *testing.T) {
	base := func() *Post { return &Post{Slug: "ok", Title: "Title", Date: "2026-08-21"} }

	if err := base().Validate(); err != nil {
		t.Fatalf("valid post rejected: %v", err)
	}

	bad := map[string]*Post{
		"traversal slug": {Slug: "../evil", Title: "T", Date: "2026-08-21"},
		"empty title":    {Slug: "ok", Title: "   ", Date: "2026-08-21"},
		"newline title":  {Slug: "ok", Title: "a\nb", Date: "2026-08-21"},
		"bad date shape": {Slug: "ok", Title: "T", Date: "21-08-2026"},
		"unreal date":    {Slug: "ok", Title: "T", Date: "2026-13-45"},
		"long title":     {Slug: "ok", Title: strings.Repeat("x", MaxTitle+1), Date: "2026-08-21"},
		"long body":      {Slug: "ok", Title: "T", Date: "2026-08-21", Body: strings.Repeat("x", MaxBody+1)},
	}
	for name, p := range bad {
		if err := p.Validate(); !errors.Is(err, ErrInvalid) {
			t.Errorf("%s: Validate() = %v, want ErrInvalid", name, err)
		}
	}

	p := &Post{Slug: "ok", Title: "  padded  ", Date: "2026-08-21"}
	if err := p.Validate(); err != nil || p.Title != "padded" {
		t.Errorf("Validate did not trim title: %q, %v", p.Title, err)
	}
}

func TestMarshalRoundTrip(t *testing.T) {
	in := &Post{Slug: "round", Title: "A: title with a colon", Date: "2026-08-21", Draft: true, Body: "# Head\n\nBody with --- inside.\n"}
	out, err := Unmarshal("round", in.Marshal())
	if err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if out.Title != in.Title {
		t.Errorf("title = %q, want %q", out.Title, in.Title)
	}
	if out.Date != in.Date || !out.Draft || out.Body != in.Body {
		t.Errorf("round trip mismatch: %+v", out)
	}
}

func TestUnmarshalRejectsGarbage(t *testing.T) {
	for _, data := range []string{"", "no front matter", "---\ntitle: x\n"} {
		if _, err := Unmarshal("s", []byte(data)); !errors.Is(err, ErrInvalid) {
			t.Errorf("Unmarshal(%q) = %v, want ErrInvalid", data, err)
		}
	}
}

func TestStoreCRUD(t *testing.T) {
	s, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}

	if _, err := s.Get("missing"); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get(missing) = %v, want ErrNotFound", err)
	}
	if err := s.Delete("missing"); !errors.Is(err, ErrNotFound) {
		t.Errorf("Delete(missing) = %v, want ErrNotFound", err)
	}

	older := &Post{Slug: "older", Title: "Older", Date: "2026-01-01", Body: "one"}
	newer := &Post{Slug: "newer", Title: "Newer", Date: "2026-08-21", Body: "two", Draft: true}

	for _, p := range []*Post{older, newer} {
		if err := s.Save(p); err != nil {
			t.Fatalf("Save(%s): %v", p.Slug, err)
		}
	}

	got, err := s.Get("newer")
	if err != nil {
		t.Fatal(err)
	}
	if got.Body != "two\n" || !got.Draft {
		t.Errorf("Get(newer) = %+v", got)
	}
	if got.UpdatedAt.IsZero() {
		t.Error("UpdatedAt not populated")
	}

	list, err := s.List()
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 2 || list[0].Slug != "newer" {
		t.Fatalf("List not sorted newest first: %+v", list)
	}
	if list[0].Body != "" {
		t.Error("List should not carry post bodies")
	}

	if err := s.Delete("older"); err != nil {
		t.Fatal(err)
	}
	if s.Exists("older") {
		t.Error("Exists(older) = true after delete")
	}
}

func TestStoreRejectsTraversal(t *testing.T) {
	s, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, slug := range []string{"../escape", "a/b", ".."} {
		if _, err := s.Get(slug); !errors.Is(err, ErrInvalid) {
			t.Errorf("Get(%q) = %v, want ErrInvalid", slug, err)
		}
		if err := s.Delete(slug); !errors.Is(err, ErrInvalid) {
			t.Errorf("Delete(%q) = %v, want ErrInvalid", slug, err)
		}
	}
}

func TestStoreSaveIsAtomic(t *testing.T) {
	dir := t.TempDir()
	s, err := NewStore(dir)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Save(&Post{Slug: "post", Title: "T", Date: "2026-08-21", Body: "body"}); err != nil {
		t.Fatal(err)
	}
	list, err := s.List()
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 1 {
		t.Fatalf("temp files leaked into List: %+v", list)
	}
}

func TestRepoConfigured(t *testing.T) {
	full := Repo{BaseURL: "u", ProjectID: "1", Token: "t", Branch: "pre", PostsPath: "p"}
	if !full.Configured() {
		t.Error("fully populated Repo reported unconfigured")
	}
	partial := Repo{BaseURL: "u", ProjectID: "1", Token: "t", Branch: "pre"}
	if partial.Configured() {
		t.Error("Repo missing PostsPath reported configured")
	}
}

func TestPublishCreatesThenUpdates(t *testing.T) {
	var actions []commitAction
	var messages []string
	present := false

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("PRIVATE-TOKEN") != "secret" {
			t.Errorf("missing token header")
		}
		if strings.Contains(r.URL.Path, "/repository/files/") {
			if !present {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			w.WriteHeader(http.StatusOK)
			return
		}
		var body struct {
			Branch  string         `json:"branch"`
			Message string         `json:"commit_message"`
			Actions []commitAction `json:"actions"`
		}
		json.NewDecoder(r.Body).Decode(&body)
		if body.Branch != "pre" {
			t.Errorf("commit branch = %q, want pre", body.Branch)
		}
		actions = append(actions, body.Actions...)
		messages = append(messages, body.Message)
		present = true
		w.WriteHeader(http.StatusCreated)
	}))
	defer srv.Close()

	repo := &Repo{BaseURL: srv.URL, ProjectID: "vinnel-cloud/gaia", Token: "secret", Branch: "pre", PostsPath: "hestia/sites/vin-moe/site/posts", Client: srv.Client()}
	p := &Post{Slug: "hello", Title: "Hello", Date: "2026-08-21", Draft: true, Body: "hi"}

	if err := repo.Publish(context.Background(), p, "a@vin.moe"); err != nil {
		t.Fatalf("first Publish: %v", err)
	}
	if err := repo.Publish(context.Background(), p, "a@vin.moe"); err != nil {
		t.Fatalf("second Publish: %v", err)
	}

	if len(actions) != 2 || actions[0].Action != "create" || actions[1].Action != "update" {
		t.Fatalf("actions = %+v, want create then update", actions)
	}
	if actions[0].FilePath != "hestia/sites/vin-moe/site/posts/hello.md" {
		t.Errorf("file path = %q", actions[0].FilePath)
	}
	raw, err := base64.StdEncoding.DecodeString(actions[0].Content)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), "draft: true") {
		t.Error("published file still marked draft")
	}
	if !strings.Contains(messages[0], "Hello") {
		t.Errorf("commit message = %q", messages[0])
	}
}

func TestUnpublishSkipsMissingFile(t *testing.T) {
	commits := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/repository/files/") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		commits++
		w.WriteHeader(http.StatusCreated)
	}))
	defer srv.Close()

	repo := &Repo{BaseURL: srv.URL, ProjectID: "p", Token: "t", Branch: "pre", PostsPath: "posts", Client: srv.Client()}
	if err := repo.Unpublish(context.Background(), "gone", "a@vin.moe"); err != nil {
		t.Fatalf("Unpublish: %v", err)
	}
	if commits != 0 {
		t.Errorf("committed %d times for a file that does not exist", commits)
	}
}

func TestPublishSurfacesGitlabError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/repository/files/") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusForbidden)
		w.Write([]byte(`{"message":"403 Forbidden"}`))
	}))
	defer srv.Close()

	repo := &Repo{BaseURL: srv.URL, ProjectID: "p", Token: "t", Branch: "pre", PostsPath: "posts", Client: srv.Client()}
	err := repo.Publish(context.Background(), &Post{Slug: "x", Title: "X", Date: "2026-08-21"}, "a@vin.moe")
	if err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("Publish error = %v, want one mentioning 403", err)
	}
}

func TestPublishRefusesUnconfigured(t *testing.T) {
	repo := &Repo{}
	if err := repo.Publish(context.Background(), &Post{Slug: "x", Title: "X", Date: "2026-08-21"}, "a"); !errors.Is(err, ErrInvalid) {
		t.Errorf("Publish on unconfigured Repo = %v, want ErrInvalid", err)
	}
}

func TestRenderHTML(t *testing.T) {
	html, err := RenderHTML("# Head\n\nText with `code` and **bold**.\n\n- one\n- two\n")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"<h1", "<code>code</code>", "<strong>bold</strong>", "<li>one</li>"} {
		if !strings.Contains(html, want) {
			t.Errorf("rendered HTML missing %q:\n%s", want, html)
		}
	}
}

func TestPublishedExcludesDrafts(t *testing.T) {
	s, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	posts := []*Post{
		{Slug: "live-old", Title: "Old", Date: "2026-01-01", Body: "old body"},
		{Slug: "live-new", Title: "New", Date: "2026-08-21", Body: "new body"},
		{Slug: "hidden", Title: "Hidden", Date: "2026-12-01", Body: "SECRET DRAFT", Draft: true},
	}
	for _, p := range posts {
		if err := s.Save(p); err != nil {
			t.Fatal(err)
		}
	}

	got, err := s.Published()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 {
		t.Fatalf("Published returned %d posts, want 2: %+v", len(got), got)
	}
	if got[0].Slug != "live-new" {
		t.Errorf("Published not sorted newest first: %+v", got)
	}
	for _, p := range got {
		if strings.Contains(p.HTML, "SECRET DRAFT") || p.Slug == "hidden" {
			t.Fatal("draft leaked into Published output")
		}
		if p.HTML == "" {
			t.Errorf("%s rendered to empty HTML", p.Slug)
		}
	}
}

func TestFeedIsValidAtom(t *testing.T) {
	cfg := FeedConfig{Title: "vin.moe", Subtitle: "sub", SiteURL: "https://vin.moe", Author: "Finlay", Email: "a@vin.moe"}
	body, err := Feed(cfg, []Rendered{{Slug: "hello", Title: "Hello & <goodbye>", Date: "2026-08-21", HTML: "<p>hi</p>"}})
	if err != nil {
		t.Fatal(err)
	}

	var parsed struct {
		XMLName xml.Name `xml:"feed"`
		Entries []struct {
			Title   string `xml:"title"`
			ID      string `xml:"id"`
			Content string `xml:"content"`
			Link    struct {
				Href string `xml:"href,attr"`
			} `xml:"link"`
		} `xml:"entry"`
	}
	if err := xml.Unmarshal(body, &parsed); err != nil {
		t.Fatalf("feed is not well-formed XML: %v\n%s", err, body)
	}
	if len(parsed.Entries) != 1 {
		t.Fatalf("entries = %d, want 1", len(parsed.Entries))
	}
	e := parsed.Entries[0]
	if e.Title != "Hello & <goodbye>" {
		t.Errorf("title did not round-trip through XML escaping: %q", e.Title)
	}
	if e.Content != "<p>hi</p>" {
		t.Errorf("content = %q", e.Content)
	}
	if e.Link.Href != "https://vin.moe/posts/hello" {
		t.Errorf("link = %q", e.Link.Href)
	}
	if e.ID != "tag:vin.moe,2026:post/hello" {
		t.Errorf("id = %q", e.ID)
	}
}

func TestFeedWithNoPosts(t *testing.T) {
	body, err := Feed(FeedConfig{SiteURL: "https://vin.moe"}, nil)
	if err != nil {
		t.Fatal(err)
	}
	var parsed struct {
		XMLName xml.Name `xml:"feed"`
	}
	if err := xml.Unmarshal(body, &parsed); err != nil {
		t.Fatalf("empty feed is not well-formed: %v\n%s", err, body)
	}
}

func TestPurgerSkipsWhenUnconfigured(t *testing.T) {
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
	}))
	defer srv.Close()

	p := &Purger{Client: srv.Client()}
	if err := p.Purge(context.Background()); err != nil {
		t.Errorf("unconfigured Purge returned %v, want nil", err)
	}
	var nilPurger *Purger
	if nilPurger.Configured() {
		t.Error("nil Purger reported configured")
	}
	if err := nilPurger.Purge(context.Background()); err != nil {
		t.Errorf("nil Purge returned %v, want nil", err)
	}
	if calls != 0 {
		t.Errorf("unconfigured purger made %d requests", calls)
	}
}

func TestPurgerPostsFileList(t *testing.T) {
	var body map[string][]string
	var auth string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth = r.Header.Get("Authorization")
		json.NewDecoder(r.Body).Decode(&body)
		w.Write([]byte(`{"success":true}`))
	}))
	defer srv.Close()

	p := &Purger{ZoneID: "zone", Token: "cf-token", URLs: []string{"https://vin.moe/posts.json"}, Client: srv.Client()}
	if !p.Configured() {
		t.Fatal("configured purger reported otherwise")
	}
	p.endpointOverride = srv.URL
	if err := p.Purge(context.Background()); err != nil {
		t.Fatalf("Purge: %v", err)
	}
	if auth != "Bearer cf-token" {
		t.Errorf("Authorization = %q", auth)
	}
	if len(body["files"]) != 1 || body["files"][0] != "https://vin.moe/posts.json" {
		t.Errorf("files = %v", body["files"])
	}

	if err := p.Purge(context.Background(), "https://vin.moe/posts/hello"); err != nil {
		t.Fatalf("Purge with extra: %v", err)
	}
	if len(body["files"]) != 2 || body["files"][1] != "https://vin.moe/posts/hello" {
		t.Errorf("files with extra = %v", body["files"])
	}
	if len(p.URLs) != 1 {
		t.Errorf("extra URLs leaked into the purger: %v", p.URLs)
	}
}
