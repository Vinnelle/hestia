package tools

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestCalculate(t *testing.T) {
	for expr, want := range map[string]string{
		"3^3^3":              "7625597484987",
		"1 + 2 * 3":          "7",
		"(1 + 2) * 3":        "9",
		"-2^2":               "-4",
		"2^-1":               "0.5",
		"10 % 4":             "2",
		"5!":                 "120",
		"sqrt(16) + abs(-3)": "7",
		"max(1, 7, 3)":       "7",
		"2 ** 10":            "1024",
		"6 × 7 ÷ 2":          "21",
		"1e3 / 8":            "125",
		"round(pi * 100)":    "314",
		"2^60":               "1.15292150460685e+18",
	} {
		got, err := Calculate(expr)
		if err != nil || got != want {
			t.Errorf("Calculate(%q) = %q, %v; want %q", expr, got, err, want)
		}
	}
	for _, expr := range []string{"1 / 0", "2 +", "foo(1)", "sqrt 4", "(1 + 2", "171!", "1,000", strings.Repeat("(", 100) + "1" + strings.Repeat(")", 100), "10^400"} {
		if got, err := Calculate(expr); err == nil {
			t.Errorf("Calculate(%q) = %q; want an error", expr, got)
		}
	}
}

func TestNotebook(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notes.json")
	at := time.Date(2026, 10, 28, 12, 0, 0, 0, time.UTC)
	n, err := OpenNotebook(path, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := n.Add("  bob likes\nrust  ", at); err != nil || got != "saved as note 1" {
		t.Fatalf("Add = %q, %v", got, err)
	}
	n.Add("alice runs arch", at)
	if _, err := n.Add("BOB LIKES RUST", at); err == nil {
		t.Error("a duplicate note was saved")
	}
	if _, err := n.Add(strings.Repeat("x", NoteChars+1), at); err == nil {
		t.Error("an overlong note was saved")
	}
	if got, err := n.Forget(1); err != nil || got != "crossed out note 1" {
		t.Fatalf("Forget = %q, %v", got, err)
	}
	if _, err := n.Forget(1); err == nil {
		t.Error("forgot a note twice")
	}

	again, err := OpenNotebook(path, t.Logf)
	if err != nil {
		t.Fatal(err)
	}
	notes := again.Notes()
	if len(notes) != 1 || notes[0].ID != 2 || notes[0].Text != "alice runs arch" {
		t.Fatalf("reopened notes = %+v", notes)
	}
	if got, _ := again.Add("third", at); got != "saved as note 3" {
		t.Errorf("numbers restarted after reopening: %q", got)
	}
	for i := len(again.Notes()); i < MaxNotes; i++ {
		if _, err := again.Add(strings.Repeat("n", i+1), at); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := again.Add("one too many", at); err == nil || !strings.Contains(err.Error(), "full") {
		t.Errorf("a full notebook took another note: %v", err)
	}
}

func TestNotebookSetsAsideBadFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notes.json")
	os.WriteFile(path, []byte("{not json"), 0o600)
	var logged []string
	n, err := OpenNotebook(path, func(f string, a ...any) { logged = append(logged, f) })
	if err != nil || len(n.Notes()) != 0 || len(logged) != 1 {
		t.Fatalf("OpenNotebook = %v, %d notes, logged %q", err, len(n.Notes()), logged)
	}
	if _, err := os.Stat(path + ".bad"); err != nil {
		t.Error("the bad notebook wasn't kept aside")
	}
}

func TestSearch(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/search" || r.URL.Query().Get("format") != "json" || r.URL.Query().Get("q") != "chat vin.moe" {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{
			"answers": []any{"42", map[string]string{"answer": "an object answer"}},
			"results": []map[string]string{
				{"title": "chat", "url": "https://chat.vin.moe", "content": "an  encrypted\nterminal chat"},
				{"title": "dupe", "url": "https://chat.vin.moe"},
				{"title": "GitHub", "url": "https://github.com/Vinnelle/chat", "content": strings.Repeat("y", 400)},
			},
		})
	}))
	defer srv.Close()
	got, err := (&Searcher{BaseURL: srv.URL + "/"}).Search(context.Background(), " chat vin.moe ")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"answer: 42", "answer: an object answer", "1. chat <https://chat.vin.moe>: an encrypted terminal chat", "2. GitHub <https://github.com/Vinnelle/chat>: yyy"} {
		if !strings.Contains(got, want) {
			t.Errorf("results lack %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "dupe") || strings.Contains(got, strings.Repeat("y", snippetChars+1)) {
		t.Errorf("duplicate or long snippet kept:\n%s", got)
	}

	srv.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Error(w, "no", http.StatusForbidden) })
	if _, err := (&Searcher{BaseURL: srv.URL}).Search(context.Background(), "x"); err == nil || !strings.Contains(err.Error(), "403") {
		t.Errorf("a 403 gave %v", err)
	}
}

func TestCheckURL(t *testing.T) {
	for link, ok := range map[string]bool{
		"https://example.com/a":          true,
		"http://example.onion/":          true,
		"https://93.184.215.14/":         true,
		"ftp://example.com/":             false,
		"file:///etc/passwd":             false,
		"https://localhost/":             false,
		"http://127.0.0.1:8080/":         false,
		"http://10.0.0.1/":               false,
		"http://[::1]/":                  false,
		"http://[::ffff:10.0.0.1]/":      false,
		"http://100.100.1.1/":            false,
		"http://169.254.169.254/latest":  false,
		"http://llm.llm.svc:8080/v1":     false,
		"http://searxng/":                false,
		"http://router.lan/":             false,
		"https://user:pw@example.com/":   false,
		"http://kube.cluster.local./api": false,
	} {
		u, _ := url.Parse(link)
		if err := checkURL(u); (err == nil) != ok {
			t.Errorf("checkURL(%s) = %v", link, err)
		}
	}
}

type pages map[string][2]string

func (p pages) RoundTrip(r *http.Request) (*http.Response, error) {
	resp := &http.Response{StatusCode: http.StatusNotFound, Status: "404 Not Found", Header: http.Header{}, Body: io.NopCloser(strings.NewReader("")), Request: r}
	if pg, ok := p[r.URL.String()]; ok {
		resp.StatusCode, resp.Status = http.StatusOK, "200 OK"
		resp.Header.Set("Content-Type", pg[0])
		resp.Body = io.NopCloser(strings.NewReader(pg[1]))
	}
	return resp, nil
}

func page(kind, body string) [2]string {
	return [2]string{kind, body}
}

func TestRead(t *testing.T) {
	article := "<p>" + strings.Repeat("Foxes are small omnivores. ", 10) + "</p><p>The red fox lives in the north.</p><p>Arctic foxes turn white in winter.</p>"
	r := &Reader{HTTP: &http.Client{Transport: pages{
		"https://example.com/fox": page("text/html; charset=utf-8", `<html><head><title>Foxes</title><style>p{}</style></head><body>
			<nav>Home | About</nav><script>alert(1)</script><main>`+article+`</main><footer>(c) 2026</footer></body></html>`),
		"https://example.com/plain": page("text/plain", "just text"),
		"https://example.com/pic":   page("image/png", "\x89PNG"),
	}}}
	got, err := r.Read(context.Background(), "example.com/fox#top", "")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got, "Foxes\n") || !strings.Contains(got, "Arctic foxes turn white") {
		t.Errorf("page text:\n%s", got)
	}
	for _, junk := range []string{"alert", "Home | About", "(c) 2026", "p{}"} {
		if strings.Contains(got, junk) {
			t.Errorf("page text kept %q:\n%s", junk, got)
		}
	}
	got, _ = r.Read(context.Background(), "https://example.com/fox", "arctic winter")
	if !strings.Contains(got, "Arctic foxes") || strings.Contains(got, "omnivores") {
		t.Errorf("find gave:\n%s", got)
	}
	if got, err := r.Read(context.Background(), "https://example.com/plain", ""); err != nil || got != "just text" {
		t.Errorf("plain text = %q, %v", got, err)
	}
	if _, err := r.Read(context.Background(), "https://example.com/pic", ""); err == nil || !strings.Contains(err.Error(), "image/png") {
		t.Errorf("an image gave %v", err)
	}
	if _, err := r.Read(context.Background(), "https://example.com/gone", ""); err == nil || !strings.Contains(err.Error(), "404") {
		t.Errorf("a 404 gave %v", err)
	}
	if _, err := r.Read(context.Background(), "http://10.1.2.3/", ""); err == nil {
		t.Error("read a private address")
	}
}

func TestExcerpt(t *testing.T) {
	long := strings.Repeat("filler line\n", 1000) + "the answer is here"
	if got := excerpt(long, "", 100); len(got) > 130 || !strings.HasSuffix(got, "(…the page goes on)") {
		t.Errorf("excerpt wasn't cut: %q", got)
	}
	if got := excerpt(long, "answer", 100); got != "the answer is here" {
		t.Errorf("find gave %q", got)
	}
	if got := excerpt("a\nb", "missing", 100); !strings.HasPrefix(got, "(nothing on the page mentions missing") {
		t.Errorf("a miss gave %q", got)
	}
}

func TestToolbox(t *testing.T) {
	box := &Toolbox{Notes: &Notebook{next: 1}, Now: func() time.Time { return time.Date(2026, 10, 28, 14, 3, 0, 0, time.UTC) }}
	var schema map[string]any
	if err := json.Unmarshal(box.Schema(), &schema); err != nil {
		t.Fatalf("schema isn't JSON: %v\n%s", err, box.Schema())
	}
	if s := string(box.Schema()); strings.Contains(s, `"search"`) || !strings.Contains(s, `"forget"`) {
		t.Errorf("schema offers the wrong tools: %s", s)
	}
	if d := box.Describe(); strings.Contains(d, "search (") || !strings.Contains(d, "note (text)") {
		t.Errorf("Describe = %s", d)
	}

	plan, err := ParsePlan(`{"need":"time and a sum","tools":[{"tool":"time","zone":"Europe/London"},{"tool":"calculate","expression":"2+2"},{"tool":"note","text":"bob likes rust"},{"tool":"search","query":"x"}]}`)
	if err != nil {
		t.Fatal(err)
	}
	results := box.Run(context.Background(), plan.Tools)
	if len(results) != 3 {
		t.Fatalf("ran %d calls; want %d", len(results), MaxCalls)
	}
	want := []string{"Wednesday 28 October 2026, 14:03 GMT (UTC+00:00) in Europe/London", "4", "saved as note 1"}
	for i, r := range results {
		if r.Err != nil || r.Text != want[i] {
			t.Errorf("%s = %q, %v; want %q", r.Call, r.Text, r.Err, want[i])
		}
	}
	if got := box.Run(context.Background(), []Call{{Tool: "search", Query: "x"}}); got[0].Err == nil {
		t.Error("ran a search with no search engine")
	}
	if _, err := box.time("Mars/Olympus"); err == nil {
		t.Error("accepted an unknown zone")
	}
	if nb := box.Notebook(); !strings.Contains(nb, "1. (28 Oct 2026) bob likes rust") {
		t.Errorf("Notebook = %q", nb)
	}
}

func TestPageTextDropsMenus(t *testing.T) {
	_, text := pageText(`<body><main><div><ul><li><a href="/de">Deutsch</a></li><li><a href="/fr">Français</a></li><li><a href="/es">Español</a></li></ul></div>
		<p>` + strings.Repeat("Foxes are small. ", 15) + `</p><ul><li>red fox</li><li>arctic fox</li><li><a href="/f">fennec</a> fox</li></ul>
		<div role="navigation">Skip to content</div></main></body>`)
	if strings.Contains(text, "Deutsch") || strings.Contains(text, "Skip to content") || !strings.Contains(text, "- arctic fox") {
		t.Errorf("page text:\n%s", text)
	}
}

func TestExcerptPrefersLinesWithMoreWords(t *testing.T) {
	text := strings.Repeat("the fox runs\n", 50) + "the arctic fox is white\n" + strings.Repeat("filler\n", 50)
	if got := excerpt(text, "arctic fox", 200); !strings.Contains(got, "the arctic fox is white\n") {
		t.Errorf("excerpt = %q", got)
	}
}
