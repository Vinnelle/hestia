package tools

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"golang.org/x/net/html"
	"golang.org/x/net/html/atom"
)

const (
	maxURL       = 2000
	maxPage      = 2 << 20
	pageChars    = 3000
	maxRedirects = 5
	readTimeout  = 25 * time.Second
	userAgent    = "Mozilla/5.0 (Windows NT 10.0; rv:140.0) Gecko/20100101 Firefox/140.0"
)

type Reader struct {
	HTTP *http.Client
}

// Pages go through tor's SOCKS port, which resolves names itself, so neither
// the page nor its DNS ever leaves from the cluster's own address.
func TorReader(socks string) *Reader {
	proxy := &url.URL{Scheme: "socks5h", Host: socks}
	return &Reader{HTTP: &http.Client{
		Transport: &http.Transport{
			Proxy:                 http.ProxyURL(proxy),
			TLSHandshakeTimeout:   20 * time.Second,
			ResponseHeaderTimeout: 30 * time.Second,
			MaxIdleConns:          4,
			IdleConnTimeout:       30 * time.Second,
		},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= maxRedirects {
				return errors.New("too many redirects")
			}
			return checkURL(req.URL)
		},
	}}
}

var privateSuffixes = []string{".local", ".localhost", ".internal", ".lan", ".home.arpa", ".svc", ".cluster.local", ".localdomain"}

func checkURL(u *url.URL) error {
	if u.Scheme != "http" && u.Scheme != "https" {
		return errors.New("only http and https links can be read")
	}
	if u.User != nil {
		return errors.New("links with a user name or password aren't read")
	}
	host := strings.TrimSuffix(strings.ToLower(u.Hostname()), ".")
	if host == "" {
		return errors.New("the link has no host")
	}
	if ip, err := netip.ParseAddr(host); err == nil {
		if !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.Is4In6() || isShared(ip) {
			return errors.New("that address isn't on the public internet")
		}
		return nil
	}
	if !strings.Contains(host, ".") || host == "localhost" {
		return errors.New("that host isn't on the public internet")
	}
	for _, s := range privateSuffixes {
		if strings.HasSuffix(host, s) {
			return errors.New("that host isn't on the public internet")
		}
	}
	return nil
}

var shared = netip.MustParsePrefix("100.64.0.0/10")

func isShared(ip netip.Addr) bool {
	return shared.Contains(ip)
}

func (r *Reader) Read(ctx context.Context, link, find string) (string, error) {
	link = strings.TrimSpace(link)
	if len(link) > maxURL {
		return "", fmt.Errorf("the link is over %d characters", maxURL)
	}
	if !strings.Contains(link, "://") {
		link = "https://" + link
	}
	u, err := url.Parse(link)
	if err != nil {
		return "", errors.New("that isn't a link")
	}
	u.Fragment = ""
	if err := checkURL(u); err != nil {
		return "", err
	}
	got, err := r.get(ctx, u, "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5")
	if err != nil {
		return "", err
	}
	var title, text string
	if got.kind == "" || got.kind == "text/html" || got.kind == "application/xhtml+xml" {
		title, text = pageText(got.body)
	} else {
		text = got.body
	}
	text = excerpt(text, find, pageChars)
	if text == "" {
		return "", errors.New("the page has no text to read; it may need JavaScript")
	}
	var b strings.Builder
	if title != "" {
		fmt.Fprintf(&b, "%s\n", flatten(title, 200))
	}
	if got.final != u.String() {
		fmt.Fprintf(&b, "(redirected to <%s>)\n", got.final)
	}
	b.WriteString(text)
	return b.String(), nil
}

type fetched struct {
	kind  string
	body  string
	final string
}

type statusError struct {
	code   int
	status string
}

func (e *statusError) Error() string {
	hint := ""
	if e.code == http.StatusForbidden || e.code == http.StatusTooManyRequests || e.code == http.StatusServiceUnavailable {
		hint = " (some sites block Tor)"
	}
	return fmt.Sprintf("the site said %s%s", e.status, hint)
}

func notFound(err error) bool {
	s, ok := errors.AsType[*statusError](err)
	return ok && s.code == http.StatusNotFound
}

func (r *Reader) get(ctx context.Context, u *url.URL, accept string) (fetched, error) {
	ctx, cancel := context.WithTimeout(ctx, readTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return fetched{}, err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", accept)
	req.Header.Set("Accept-Language", "en-US,en;q=0.5")
	resp, err := r.HTTP.Do(req)
	if err != nil {
		err = withoutURL(err)
		var ne net.Error
		if errors.As(err, &ne) && ne.Timeout() || errors.Is(err, context.DeadlineExceeded) {
			return fetched{}, errors.New("the page took too long to load over Tor")
		}
		return fetched{}, fmt.Errorf("couldn't load the page over Tor: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fetched{}, &statusError{resp.StatusCode, resp.Status}
	}
	kind, _, _ := mime.ParseMediaType(resp.Header.Get("Content-Type"))
	textual := strings.HasPrefix(kind, "text/") || kind == "application/json" || strings.HasSuffix(kind, "+xml") || strings.HasSuffix(kind, "/xml")
	if kind != "" && !textual {
		return fetched{}, fmt.Errorf("it's %s, not a page with text to read", kind)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxPage))
	if err != nil {
		return fetched{}, fmt.Errorf("the page stopped loading: %w", withoutURL(err))
	}
	if kind == "" && !utf8.Valid(body[:min(len(body), 512)]) {
		return fetched{}, errors.New("it isn't a page with text to read")
	}
	return fetched{kind: kind, body: strings.ToValidUTF8(string(body), ""), final: resp.Request.URL.String()}, nil
}

var skipped = map[atom.Atom]bool{
	atom.Script: true, atom.Style: true, atom.Noscript: true, atom.Template: true, atom.Svg: true,
	atom.Iframe: true, atom.Head: true, atom.Nav: true, atom.Footer: true, atom.Aside: true,
	atom.Form: true, atom.Button: true, atom.Select: true, atom.Dialog: true, atom.Canvas: true,
}

var blocks = map[atom.Atom]bool{
	atom.P: true, atom.Div: true, atom.Br: true, atom.Li: true, atom.H1: true, atom.H2: true,
	atom.H3: true, atom.H4: true, atom.H5: true, atom.H6: true, atom.Tr: true, atom.Section: true,
	atom.Article: true, atom.Header: true, atom.Pre: true, atom.Blockquote: true, atom.Dd: true,
	atom.Dt: true, atom.Table: true, atom.Ul: true, atom.Ol: true, atom.Figure: true,
	atom.Figcaption: true, atom.Main: true, atom.Hr: true, atom.Td: true, atom.Th: true,
}

func pageText(page string) (string, string) {
	doc, err := html.Parse(strings.NewReader(strings.ToValidUTF8(page, "")))
	if err != nil {
		return "", ""
	}
	var title string
	var main, body *html.Node
	var find func(*html.Node)
	find = func(n *html.Node) {
		if n.Type == html.ElementNode {
			switch n.DataAtom {
			case atom.Title:
				if title == "" && n.FirstChild != nil {
					title = n.FirstChild.Data
				}
			case atom.Main, atom.Article:
				if main == nil {
					main = n
				}
			case atom.Body:
				body = n
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			find(c)
		}
	}
	find(doc)
	root := body
	if root == nil {
		root = doc
	}
	if main != nil {
		if text := nodeText(main); len(text) >= 200 {
			return title, text
		}
	}
	return title, nodeText(root)
}

func nodeText(root *html.Node) string {
	var b strings.Builder
	var walk func(*html.Node)
	walk = func(n *html.Node) {
		switch n.Type {
		case html.TextNode:
			if s := strings.Join(strings.Fields(n.Data), " "); s != "" {
				if b.Len() > 0 && !strings.HasSuffix(b.String(), "\n") && !strings.HasSuffix(b.String(), " ") {
					b.WriteByte(' ')
				}
				b.WriteString(s)
			}
			return
		case html.ElementNode:
			if skipped[n.DataAtom] || hidden(n) || menu(n) {
				return
			}
		}
		block := n.Type == html.ElementNode && blocks[n.DataAtom]
		if block {
			b.WriteByte('\n')
			if n.DataAtom == atom.Li {
				b.WriteString("- ")
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			walk(c)
		}
		if block {
			b.WriteByte('\n')
		}
	}
	walk(root)
	var lines []string
	for line := range strings.SplitSeq(b.String(), "\n") {
		if line = strings.TrimSpace(line); line != "" && line != "-" {
			lines = append(lines, line)
		}
	}
	return strings.Join(lines, "\n")
}

var menuRoles = map[string]bool{"navigation": true, "menu": true, "menubar": true, "banner": true, "contentinfo": true, "search": true, "toolbar": true, "tablist": true}

func hidden(n *html.Node) bool {
	for _, a := range n.Attr {
		switch a.Key {
		case "hidden":
			return true
		case "aria-hidden":
			return a.Val == "true"
		case "role":
			return menuRoles[a.Val]
		}
	}
	return false
}

// menu spots lists that are nothing but links, such as a language picker or a
// site menu inside <main>, which would otherwise fill the excerpt.
func menu(n *html.Node) bool {
	if n.DataAtom != atom.Ul && n.DataAtom != atom.Ol {
		return false
	}
	items := 0
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		if c.Type == html.ElementNode && c.DataAtom == atom.Li {
			items++
		}
	}
	all, linked := textSize(n, false)
	return items >= 3 && all > 0 && linked*10 >= all*9
}

func textSize(n *html.Node, inLink bool) (all, linked int) {
	if n.Type == html.TextNode {
		size := len(strings.TrimSpace(n.Data))
		if inLink {
			return size, size
		}
		return size, 0
	}
	inLink = inLink || n.Type == html.ElementNode && n.DataAtom == atom.A
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		a, l := textSize(c, inLink)
		all, linked = all+a, linked+l
	}
	return all, linked
}

// excerpt keeps the start of a long page, or with find, the lines that mention
// the most of its words and the line after each, so a long article still fits.
func excerpt(text, find string, limit int) string {
	var words []string
	for _, w := range strings.Fields(strings.ToLower(find)) {
		if len(w) > 2 {
			words = append(words, w)
		}
	}
	if len(words) == 0 {
		return truncate(text, limit)
	}
	lines := strings.Split(text, "\n")
	scores := make([]int, len(lines))
	best := 0
	for i, line := range lines {
		lower := strings.ToLower(line)
		for _, w := range words {
			if strings.Contains(lower, w) {
				scores[i]++
			}
		}
		best = max(best, scores[i])
	}
	if best == 0 {
		return truncate("(nothing on the page mentions "+find+"; it starts:)\n"+text, limit/2)
	}
	order := make([]int, len(lines))
	for i := range order {
		order[i] = i
	}
	sort.SliceStable(order, func(a, b int) bool { return scores[order[a]] > scores[order[b]] })
	taken := map[int]bool{}
	size := 0
	for _, i := range order {
		if scores[i] == 0 || size >= limit {
			break
		}
		for j := i; j <= i+1 && j < len(lines); j++ {
			if !taken[j] {
				taken[j] = true
				size += len(lines[j]) + 1
			}
		}
	}
	var picked []string
	for i, line := range lines {
		if taken[i] {
			picked = append(picked, line)
		}
	}
	return truncate(strings.Join(picked, "\n"), limit)
}

func truncate(s string, limit int) string {
	if len(s) <= limit {
		return s
	}
	cut := limit
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return strings.TrimSpace(s[:cut]) + "\n(…the page goes on)"
}
