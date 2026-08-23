package blog

import (
	"strings"
	"testing"
)

func TestExcerpt(t *testing.T) {
	if got := Excerpt("<p>Hello <em>there</em> &amp; welcome.</p>"); got != "Hello there & welcome." {
		t.Errorf("Excerpt = %q", got)
	}
	long := Excerpt("<p>" + strings.Repeat("word ", 200) + "</p>")
	if len(long) > maxExcerpt+3 {
		t.Errorf("Excerpt length = %d, want <= %d", len(long), maxExcerpt+3)
	}
	if !strings.HasSuffix(long, "…") {
		t.Errorf("truncated excerpt = %q, want an ellipsis", long)
	}
}

func TestPage(t *testing.T) {
	cfg := FeedConfig{Title: "vin.moe", SiteURL: "https://vin.moe/", Author: "Finlay"}
	body, err := Page(cfg, Rendered{Slug: "hello", Title: "Hello & Goodbye", Date: "2026-08-21", HTML: "<p>body text</p>"})
	if err != nil {
		t.Fatal(err)
	}
	page := string(body)

	for _, want := range []string{
		`<link rel="canonical" href="https://vin.moe/posts/hello">`,
		`<meta property="og:url" content="https://vin.moe/posts/hello">`,
		`<title>Hello &amp; Goodbye &mdash; vin.moe</title>`,
		`<time datetime="2026-08-21">2026-08-21</time>`,
		`<p>body text</p>`,
		`href="/css/post.css"`,
	} {
		if !strings.Contains(page, want) {
			t.Errorf("page missing %q\n%s", want, page)
		}
	}
	if strings.Contains(page, "&lt;p&gt;body text") {
		t.Error("post HTML was double-escaped")
	}
}
