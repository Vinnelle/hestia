package blog

import (
	"bytes"
	"html"
	"html/template"
	"regexp"
	"strings"
)

const maxExcerpt = 180

var tagPattern = regexp.MustCompile(`<[^>]*>`)

func Excerpt(rendered string) string {
	text := strings.Join(strings.Fields(html.UnescapeString(tagPattern.ReplaceAllString(rendered, " "))), " ")
	if len(text) <= maxExcerpt {
		return text
	}
	cut := text[:maxExcerpt]
	if i := strings.LastIndex(cut, " "); i > 0 {
		cut = cut[:i]
	}
	return strings.TrimRight(cut, " ,.;:—-") + "…"
}

type pageData struct {
	Title    string
	Date     string
	Body     template.HTML
	URL      string
	Excerpt  string
	Site     string
	SiteName string
	Author   string
}

var postPage = template.Must(template.New("post").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{.Title}} | {{.SiteName}}</title>
<meta name="description" content="{{.Excerpt}}">
<link rel="canonical" href="{{.URL}}">
<link rel="alternate" type="application/atom+xml" title="{{.SiteName}} blog" href="/feed.xml">
<meta name="theme-color" content="#faf8f5" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0c0c0d" media="(prefers-color-scheme: dark)">
<script>try{const t=localStorage.theme;if(t)document.documentElement.dataset.theme=t}catch{}</script>
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="stylesheet" href="/fonts/post.css">
<link rel="stylesheet" href="/css/post.css">
<meta property="og:type" content="article">
<meta property="og:url" content="{{.URL}}">
<meta property="og:title" content="{{.Title}}">
<meta property="og:description" content="{{.Excerpt}}">
<meta property="og:image" content="{{.Site}}/avatar.webp">
<meta property="og:site_name" content="{{.SiteName}}">
<meta property="article:published_time" content="{{.Date}}">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="{{.Title}}">
<meta name="twitter:description" content="{{.Excerpt}}">
<meta name="twitter:image" content="{{.Site}}/avatar.webp">
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "BlogPosting",
  "headline": {{.Title}},
  "datePublished": {{.Date}},
  "url": {{.URL}},
  "author": { "@type": "Person", "name": {{.Author}}, "url": {{.Site}} }
}
</script>
</head>
<body>
<a class="skip" href="#main">skip to content</a>

<div class="bar">
  <a class="brand" href="{{.Site}}/"><span class="chip">{{.SiteName}}</span></a>
  <nav class="bar-nav" aria-label="Site">
    <span class="tabs">
      <a class="tab" href="{{.Site}}/">about</a>
      <a class="tab" href="{{.Site}}/#blog" aria-current="true">blog</a>
    </span>
    <span class="bar-sep" aria-hidden="true"></span>
    <span class="theme-toggle" role="group" aria-label="Theme">
      <button class="theme-opt" type="button" data-theme-choice="dark" aria-pressed="false">dark</button>
      <span class="sep" aria-hidden="true">/</span>
      <button class="theme-opt" type="button" data-theme-choice="light" aria-pressed="false">light</button>
    </span>
  </nav>
</div>

<main id="main">
  <article>
    <header class="page-head">
      <h1>{{.Title}}</h1>
      <p class="post-meta"><time datetime="{{.Date}}">{{.Date}}</time></p>
    </header>
    <div class="post-body post-page">{{.Body}}</div>
  </article>
  <p class="post-back"><a href="{{.Site}}/#blog"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13 8H3.5"/><path d="M7.5 4l-4 4 4 4"/></svg>all posts</a></p>
</main>

<footer>
  <nav class="foot-nav" aria-label="Source">
    <a href="/feed.xml">Atom feed</a>
    <a href="https://github.com/Vinnelle/vin.moe">Site source</a>
    <a href="https://github.com/Vinnelle/hestia">Infra source</a>
  </nav>
</footer>
<script>
(() => {
  const root = document.documentElement;
  const opts = [...document.querySelectorAll('.theme-opt')];
  const dark = matchMedia('(prefers-color-scheme: dark)');
  const sync = () => {
    const active = root.dataset.theme || (dark.matches ? 'dark' : 'light');
    for (const b of opts) b.setAttribute('aria-pressed', b.dataset.themeChoice === active);
  };
  for (const b of opts) b.addEventListener('click', () => {
    root.dataset.theme = b.dataset.themeChoice;
    try { localStorage.theme = b.dataset.themeChoice; } catch {}
    sync();
  });
  dark.addEventListener('change', sync);
  sync();
})();
</script>
</body>
</html>
`))

func Page(cfg FeedConfig, p Rendered) ([]byte, error) {
	site := strings.TrimRight(cfg.SiteURL, "/")
	data := pageData{
		Title:    p.Title,
		Date:     p.Date,
		Body:     template.HTML(p.HTML),
		URL:      cfg.postLink(p.Slug),
		Excerpt:  Excerpt(p.HTML),
		Site:     site,
		SiteName: cfg.Title,
		Author:   cfg.Author,
	}
	if data.SiteName == "" {
		data.SiteName = strings.TrimPrefix(strings.TrimPrefix(site, "https://"), "http://")
	}
	var out bytes.Buffer
	if err := postPage.Execute(&out, data); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}
