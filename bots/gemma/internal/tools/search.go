package tools

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	maxQuery      = 200
	searchResults = 5
	snippetChars  = 300
	searchTimeout = 20 * time.Second
)

type Searcher struct {
	BaseURL string
	HTTP    *http.Client
}

type searxResult struct {
	Title   string `json:"title"`
	URL     string `json:"url"`
	Content string `json:"content"`
}

type searxResponse struct {
	Results   []searxResult     `json:"results"`
	Answers   []json.RawMessage `json:"answers"`
	Infoboxes []struct {
		Infobox string `json:"infobox"`
		Content string `json:"content"`
		ID      string `json:"id"`
	} `json:"infoboxes"`
	Suggestions []string `json:"suggestions"`
}

func (s *Searcher) Search(ctx context.Context, query string) (string, error) {
	query = strings.TrimSpace(query)
	switch {
	case query == "":
		return "", errors.New("the query is empty")
	case len(query) > maxQuery:
		return "", fmt.Errorf("the query is over %d characters", maxQuery)
	}
	ctx, cancel := context.WithTimeout(ctx, searchTimeout)
	defer cancel()
	q := url.Values{"q": {query}, "format": {"json"}, "safesearch": {"1"}}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(s.BaseURL, "/")+"/search?"+q.Encode(), nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/json")
	client := s.HTTP
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("the search engine didn't answer: %w", withoutURL(err))
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("the search engine said %s", resp.Status)
	}
	var out searxResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(&out); err != nil {
		return "", fmt.Errorf("the search engine's answer wasn't JSON: %w", err)
	}

	var b strings.Builder
	for _, raw := range out.Answers {
		var answer string
		if json.Unmarshal(raw, &answer) != nil {
			var obj struct {
				Answer string `json:"answer"`
			}
			json.Unmarshal(raw, &obj)
			answer = obj.Answer
		}
		if answer = flatten(answer, snippetChars); answer != "" {
			fmt.Fprintf(&b, "answer: %s\n", answer)
		}
	}
	if len(out.Infoboxes) > 0 {
		box := out.Infoboxes[0]
		if content := flatten(box.Content, 2*snippetChars); content != "" {
			fmt.Fprintf(&b, "%s (%s): %s\n", flatten(box.Infobox, 100), box.ID, content)
		}
	}
	seen := map[string]bool{}
	n := 0
	for _, r := range out.Results {
		if n == searchResults || r.URL == "" || seen[r.URL] {
			continue
		}
		seen[r.URL] = true
		n++
		fmt.Fprintf(&b, "%d. %s <%s>", n, flatten(r.Title, 120), r.URL)
		if content := flatten(r.Content, snippetChars); content != "" {
			fmt.Fprintf(&b, ": %s", content)
		}
		b.WriteByte('\n')
	}
	if b.Len() == 0 {
		if len(out.Suggestions) > 0 {
			return "no results; the search engine suggests: " + strings.Join(out.Suggestions[:min(3, len(out.Suggestions))], ", "), nil
		}
		return "no results", nil
	}
	return strings.TrimSpace(b.String()), nil
}

func withoutURL(err error) error {
	if u, ok := errors.AsType[*url.Error](err); ok {
		return u.Err
	}
	return err
}

func flatten(s string, limit int) string {
	s = strings.Join(strings.Fields(s), " ")
	if r := []rune(s); len(r) > limit {
		s = strings.TrimSpace(string(r[:limit])) + "…"
	}
	return s
}
