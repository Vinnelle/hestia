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
	req, err := http.NewRequestWithContext(ctx, method, endpoint, body)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("PRIVATE-TOKEN", r.Token)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := r.client().Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return resp.StatusCode, data, err
}

func (r *Repo) exists(ctx context.Context, filePath string) (bool, error) {
	endpoint := r.endpoint("/repository/files/", url.PathEscape(filePath), "?ref=", url.QueryEscape(r.Branch))
	status, _, err := r.do(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return false, err
	}
	switch status {
	case http.StatusOK:
		return true, nil
	case http.StatusNotFound:
		return false, nil
	default:
		return false, fmt.Errorf("gitlab file lookup: unexpected status %d", status)
	}
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

func (r *Repo) Publish(ctx context.Context, p *Post, author string) error {
	if !r.Configured() {
		return fmt.Errorf("%w: repository publishing is not configured", ErrInvalid)
	}
	filePath, err := r.filePath(p.Slug)
	if err != nil {
		return err
	}
	present, err := r.exists(ctx, filePath)
	if err != nil {
		return err
	}
	action := "create"
	if present {
		action = "update"
	}
	live := *p
	live.Draft = false
	return r.commit(ctx, fmt.Sprintf("content(vin-moe): publish %q\n\nPublished from admin.vinnel.cloud by %s.", p.Title, author), []commitAction{{
		Action:   action,
		FilePath: filePath,
		Content:  base64.StdEncoding.EncodeToString(live.Marshal()),
		Encoding: "base64",
	}})
}

func (r *Repo) Unpublish(ctx context.Context, slug, author string) error {
	if !r.Configured() {
		return fmt.Errorf("%w: repository publishing is not configured", ErrInvalid)
	}
	filePath, err := r.filePath(slug)
	if err != nil {
		return err
	}
	present, err := r.exists(ctx, filePath)
	if err != nil {
		return err
	}
	if !present {
		return nil
	}
	return r.commit(ctx, fmt.Sprintf("content(vin-moe): unpublish %q\n\nUnpublished from admin.vinnel.cloud by %s.", slug, author), []commitAction{{
		Action:   "delete",
		FilePath: filePath,
	}})
}
