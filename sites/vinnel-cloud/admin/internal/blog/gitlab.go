package blog

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Repo struct {
	BaseURL   string
	ProjectID string
	Token     string
	Branch    string
	PostsPath string
	Client    *http.Client
}

func (r *Repo) Configured() bool {
	return r.BaseURL != "" && r.ProjectID != "" && r.Token != "" && r.Branch != "" && r.PostsPath != ""
}

func (r *Repo) client() *http.Client {
	if r.Client != nil {
		return r.Client
	}
	return &http.Client{Timeout: 20 * time.Second}
}

func (r *Repo) filePath(slug string) (string, error) {
	if !ValidSlug(slug) {
		return "", fmt.Errorf("%w: bad slug %q", ErrInvalid, slug)
	}
	return path.Join(r.PostsPath, slug+".md"), nil
}

func (r *Repo) endpoint(parts ...string) string {
	return strings.TrimRight(r.BaseURL, "/") + "/projects/" + url.PathEscape(r.ProjectID) + strings.Join(parts, "")
}

func (r *Repo) do(ctx context.Context, method, endpoint string, body io.Reader) (int, []byte, error) {
	status, data, _, err := r.doWithHeaders(ctx, method, endpoint, body)
	return status, data, err
}

func (r *Repo) doWithHeaders(ctx context.Context, method, endpoint string, body io.Reader) (int, []byte, http.Header, error) {
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return 0, nil, nil, err
	}
	req.Header.Set("PRIVATE-TOKEN", r.Token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := r.client().Do(req)
	if err != nil {
		return 0, nil, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return resp.StatusCode, data, resp.Header, err
}

type commitAction struct {
	Action   string `json:"action"`
	FilePath string `json:"file_path"`
	Content  string `json:"content,omitempty"`
	Encoding string `json:"encoding,omitempty"`
}

func (r *Repo) commit(ctx context.Context, message string, actions []commitAction) error {
	payload, err := json.Marshal(map[string]any{
		"branch":         r.Branch,
		"commit_message": message,
		"actions":        actions,
	})
	if err != nil {
		return err
	}
	status, data, err := r.do(ctx, http.MethodPost, r.endpoint("/repository/commits"), bytes.NewReader(payload))
	if err != nil {
		return err
	}
	if status < 200 || status >= 300 {
		return fmt.Errorf("gitlab commit failed (%d): %s", status, strings.TrimSpace(string(data)))
	}
	return nil
}

type treeEntry struct {
	Path string `json:"path"`
	Type string `json:"type"`
}

type fileResponse struct {
	Content  string `json:"content"`
	Encoding string `json:"encoding"`
}

func (r *Repo) tree(ctx context.Context) ([]treeEntry, error) {
	var entries []treeEntry
	for page := 1; ; page++ {
		endpoint := r.endpoint(
			"/repository/tree?path=", url.QueryEscape(strings.Trim(r.PostsPath, "/")),
			"&ref=", url.QueryEscape(r.Branch),
			"&recursive=true&per_page=100&page=", strconv.Itoa(page),
		)
		status, data, headers, err := r.doWithHeaders(ctx, http.MethodGet, endpoint, nil)
		if err != nil {
			return nil, err
		}
		if status == http.StatusNotFound {
			return entries, nil
		}
		if status < 200 || status >= 300 {
			return nil, fmt.Errorf("gitlab tree lookup failed (%d): %s", status, strings.TrimSpace(string(data)))
		}
		var pageEntries []treeEntry
		if err := json.Unmarshal(data, &pageEntries); err != nil {
			return nil, fmt.Errorf("gitlab tree response: %w", err)
		}
		entries = append(entries, pageEntries...)
		if headers.Get("X-Next-Page") == "" {
			return entries, nil
		}
	}
}

func (r *Repo) file(ctx context.Context, filePath string) ([]byte, bool, error) {
	endpoint := r.endpoint("/repository/files/", url.PathEscape(filePath), "?ref=", url.QueryEscape(r.Branch))
	status, data, err := r.do(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, false, err
	}
	if status == http.StatusNotFound {
		return nil, false, nil
	}
	if status < 200 || status >= 300 {
		return nil, false, fmt.Errorf("gitlab file lookup failed (%d): %s", status, strings.TrimSpace(string(data)))
	}
	var response fileResponse
	if err := json.Unmarshal(data, &response); err != nil {
		return nil, false, fmt.Errorf("gitlab file response: %w", err)
	}
	switch response.Encoding {
	case "":
		return []byte(response.Content), true, nil
	case "base64":
		content, err := base64.StdEncoding.DecodeString(strings.Join(strings.Fields(response.Content), ""))
		if err != nil {
			return nil, false, fmt.Errorf("gitlab file content: %w", err)
		}
		return content, true, nil
	default:
		return nil, false, fmt.Errorf("gitlab file response: unsupported encoding %q", response.Encoding)
	}
}

func isPostFile(root, filePath string) bool {
	name := path.Base(filePath)
	return path.Dir(filePath) == path.Clean(root) && strings.HasSuffix(name, ".md") && ValidSlug(strings.TrimSuffix(name, ".md"))
}

func (r *Repo) Sync(ctx context.Context, posts []*Post, author string) error {
	if !r.Configured() {
		return fmt.Errorf("%w: repository sync is not configured", ErrInvalid)
	}
	entries, err := r.tree(ctx)
	if err != nil {
		return err
	}

	desired := make(map[string][]byte, len(posts))
	for _, p := range posts {
		if p.Draft {
			continue
		}
		if err := p.Validate(); err != nil {
			return fmt.Errorf("sync %s: %w", p.Slug, err)
		}
		filePath, err := r.filePath(p.Slug)
		if err != nil {
			return err
		}
		desired[filePath] = p.Marshal()
	}

	actions := make([]commitAction, 0, len(desired)+len(entries))
	for filePath, content := range desired {
		remote, present, err := r.file(ctx, filePath)
		if err != nil {
			return err
		}
		if present && bytes.Equal(remote, content) {
			continue
		}
		action := "create"
		if present {
			action = "update"
		}
		actions = append(actions, commitAction{
			Action:   action,
			FilePath: filePath,
			Content:  base64.StdEncoding.EncodeToString(content),
			Encoding: "base64",
		})
	}
	for _, entry := range entries {
		if entry.Type == "blob" && isPostFile(r.PostsPath, entry.Path) {
			if _, ok := desired[entry.Path]; !ok {
				actions = append(actions, commitAction{Action: "delete", FilePath: entry.Path})
			}
		}
	}
	if len(actions) == 0 {
		return nil
	}
	sort.Slice(actions, func(i, j int) bool { return actions[i].FilePath < actions[j].FilePath })
	return r.commit(ctx, fmt.Sprintf("content(vin-moe): nightly sync\n\nSynchronized from admin.vinnel.cloud by %s.", author), actions)
}
