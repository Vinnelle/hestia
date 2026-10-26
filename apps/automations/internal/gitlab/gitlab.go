package gitlab

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

var ErrNotFound = errors.New("not found")

const (
	maxResponse = 16 << 20
	maxPages    = 50
)

type Client struct {
	BaseURL   string
	ProjectID string
	Token     string
	HTTP      *http.Client
}

type User struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

type MergeRequest struct {
	IID          int64    `json:"iid"`
	Title        string   `json:"title"`
	Description  string   `json:"description"`
	State        string   `json:"state"`
	SourceBranch string   `json:"source_branch"`
	TargetBranch string   `json:"target_branch"`
	SHA          string   `json:"sha"`
	WebURL       string   `json:"web_url"`
	Labels       []string `json:"labels"`
	Author       User     `json:"author"`
}

type Diff struct {
	OldPath     string `json:"old_path"`
	NewPath     string `json:"new_path"`
	Diff        string `json:"diff"`
	NewFile     bool   `json:"new_file"`
	RenamedFile bool   `json:"renamed_file"`
	DeletedFile bool   `json:"deleted_file"`
}

type Note struct {
	ID     int64  `json:"id"`
	Body   string `json:"body"`
	System bool   `json:"system"`
	Author User   `json:"author"`
}

func (c *Client) client() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 30 * time.Second}
}

func (c *Client) api(parts ...string) string {
	return strings.TrimRight(c.BaseURL, "/") + strings.Join(parts, "")
}

func (c *Client) mergeRequest(iid int64, parts ...string) string {
	return c.api(append([]string{"/projects/", url.PathEscape(c.ProjectID), "/merge_requests/", strconv.FormatInt(iid, 10)}, parts...)...)
}

func (c *Client) do(ctx context.Context, method, endpoint string, in, out any) (http.Header, error) {
	var body io.Reader
	if in != nil {
		payload, err := json.Marshal(in)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("PRIVATE-TOKEN", c.Token)
	if in != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.client().Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxResponse))
	if err != nil {
		return nil, err
	}
	where := method + " " + req.URL.Path
	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("gitlab %s: %w", where, ErrNotFound)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("gitlab %s: %d %s", where, resp.StatusCode, snippet(data))
	}
	switch v := out.(type) {
	case nil:
	case *[]byte:
		*v = data
	default:
		if err := json.Unmarshal(data, out); err != nil {
			return nil, fmt.Errorf("gitlab %s: %w", where, err)
		}
	}
	return resp.Header, nil
}

func snippet(data []byte) string {
	s := strings.TrimSpace(string(data))
	if len(s) > 200 {
		s = s[:200] + "..."
	}
	return s
}

func paged[T any](ctx context.Context, c *Client, endpoint string) ([]T, error) {
	sep := "?"
	if strings.Contains(endpoint, "?") {
		sep = "&"
	}
	var all []T
	for page := 1; page <= maxPages; page++ {
		var items []T
		headers, err := c.do(ctx, http.MethodGet, endpoint+sep+"per_page=100&page="+strconv.Itoa(page), nil, &items)
		if err != nil {
			return nil, err
		}
		all = append(all, items...)
		if headers.Get("X-Next-Page") == "" || len(items) == 0 {
			return all, nil
		}
	}
	return nil, fmt.Errorf("gitlab GET %s: more than %d pages", endpoint, maxPages)
}

func (c *Client) CurrentUser(ctx context.Context) (User, error) {
	var u User
	_, err := c.do(ctx, http.MethodGet, c.api("/user"), nil, &u)
	return u, err
}

func (c *Client) MergeRequest(ctx context.Context, iid int64) (MergeRequest, error) {
	var mr MergeRequest
	_, err := c.do(ctx, http.MethodGet, c.mergeRequest(iid), nil, &mr)
	return mr, err
}

func (c *Client) Diffs(ctx context.Context, iid int64) ([]Diff, error) {
	return paged[Diff](ctx, c, c.mergeRequest(iid, "/diffs"))
}

func (c *Client) File(ctx context.Context, filePath, ref string) ([]byte, error) {
	var data []byte
	endpoint := c.api("/projects/", url.PathEscape(c.ProjectID), "/repository/files/", url.PathEscape(filePath), "/raw?ref=", url.QueryEscape(ref))
	_, err := c.do(ctx, http.MethodGet, endpoint, nil, &data)
	return data, err
}

func (c *Client) Notes(ctx context.Context, iid int64) ([]Note, error) {
	return paged[Note](ctx, c, c.mergeRequest(iid, "/notes?sort=asc&order_by=created_at"))
}

func (c *Client) CreateNote(ctx context.Context, iid int64, body string) (Note, error) {
	var n Note
	_, err := c.do(ctx, http.MethodPost, c.mergeRequest(iid, "/notes"), map[string]string{"body": body}, &n)
	return n, err
}

func (c *Client) UpdateNote(ctx context.Context, iid, id int64, body string) (Note, error) {
	var n Note
	_, err := c.do(ctx, http.MethodPut, c.mergeRequest(iid, "/notes/", strconv.FormatInt(id, 10)), map[string]string{"body": body}, &n)
	return n, err
}
