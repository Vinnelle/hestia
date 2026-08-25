package blog

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"strings"
	"time"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/extension"
)

var markdown = goldmark.New(goldmark.WithExtensions(extension.GFM))

func RenderHTML(source string) (string, error) {
	var out bytes.Buffer
	if err := markdown.Convert([]byte(source), &out); err != nil {
		return "", err
	}
	return strings.TrimSpace(out.String()), nil
}

type Rendered struct {
	Slug  string `json:"slug"`
	Title string `json:"title"`
	Date  string `json:"date"`
	HTML  string `json:"html"`
}

func (s *Store) Published() ([]Rendered, error) {
	posts, err := s.List()
	if err != nil {
		return nil, err
	}
	out := make([]Rendered, 0, len(posts))
	for _, meta := range posts {
		if meta.Draft {
			continue
		}
		post, err := s.Get(meta.Slug)
		if err != nil {
			continue
		}
		if post.Draft {
			continue
		}
		html, err := RenderHTML(post.Body)
		if err != nil {
			return nil, fmt.Errorf("render %s: %w", post.Slug, err)
		}
		out = append(out, Rendered{Slug: post.Slug, Title: post.Title, Date: post.Date, HTML: html})
	}
	return out, nil
}

type atomFeed struct {
	XMLName  xml.Name    `xml:"http://www.w3.org/2005/Atom feed"`
	Title    string      `xml:"title"`
	Subtitle string      `xml:"subtitle"`
	Links    []atomLink  `xml:"link"`
	ID       string      `xml:"id"`
	Updated  string      `xml:"updated"`
	Author   atomAuthor  `xml:"author"`
	Entries  []atomEntry `xml:"entry"`
}

type atomLink struct {
	Rel  string `xml:"rel,attr"`
	Type string `xml:"type,attr"`
	Href string `xml:"href,attr"`
}

type atomAuthor struct {
	Name  string `xml:"name"`
	Email string `xml:"email,omitempty"`
}

type atomEntry struct {
	Title   string      `xml:"title"`
	Link    atomLink    `xml:"link"`
	ID      string      `xml:"id"`
	Updated string      `xml:"updated"`
	Content atomContent `xml:"content"`
}

type atomContent struct {
	Type string `xml:"type,attr"`
	Body string `xml:",chardata"`
}

type FeedConfig struct {
	Title    string
	Subtitle string
	SiteURL  string
	Author   string
	Email    string

	PostLinkBase string
}

func (c FeedConfig) postLink(slug string) string {
	if c.PostLinkBase != "" {
		return c.PostLinkBase + slug
	}
	return strings.TrimRight(c.SiteURL, "/") + "/posts/" + slug
}

func Feed(cfg FeedConfig, posts []Rendered) ([]byte, error) {
	site := strings.TrimRight(cfg.SiteURL, "/")
	updated := time.Now().UTC().Format(time.RFC3339)
	if len(posts) > 0 {
		updated = posts[0].Date + "T00:00:00Z"
	}

	feed := atomFeed{
		Title:    cfg.Title,
		Subtitle: cfg.Subtitle,
		Links: []atomLink{
			{Rel: "self", Type: "application/atom+xml", Href: site + "/feed.xml"},
			{Rel: "alternate", Type: "text/html", Href: site + "/"},
		},
		ID:      site + "/",
		Updated: updated,
		Author:  atomAuthor{Name: cfg.Author, Email: cfg.Email},
	}

	host := strings.TrimPrefix(strings.TrimPrefix(site, "https://"), "http://")
	for _, p := range posts {
		feed.Entries = append(feed.Entries, atomEntry{
			Title:   p.Title,
			Link:    atomLink{Rel: "alternate", Type: "text/html", Href: cfg.postLink(p.Slug)},
			ID:      fmt.Sprintf("tag:%s,%s:post/%s", host, p.Date[:4], p.Slug),
			Updated: p.Date + "T00:00:00Z",
			Content: atomContent{Type: "html", Body: p.HTML},
		})
	}

	body, err := xml.MarshalIndent(feed, "", "  ")
	if err != nil {
		return nil, err
	}
	return append([]byte(xml.Header), body...), nil
}

type sitemapURL struct {
	Loc     string `xml:"loc"`
	LastMod string `xml:"lastmod,omitempty"`
}

type sitemapSet struct {
	XMLName xml.Name     `xml:"urlset"`
	Xmlns   string       `xml:"xmlns,attr"`
	URLs    []sitemapURL `xml:"url"`
}

func Sitemap(cfg FeedConfig, posts []Rendered) ([]byte, error) {
	set := sitemapSet{Xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9"}
	set.URLs = append(set.URLs, sitemapURL{Loc: strings.TrimSuffix(cfg.postLink(""), "posts/")})
	for _, p := range posts {
		set.URLs = append(set.URLs, sitemapURL{Loc: cfg.postLink(p.Slug), LastMod: p.Date})
	}
	body, err := xml.MarshalIndent(set, "", "  ")
	if err != nil {
		return nil, err
	}
	return append([]byte(xml.Header), body...), nil
}
