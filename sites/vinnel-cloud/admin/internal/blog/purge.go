package blog

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type Purger struct {
	ZoneID string
	Token  string
	URLs   []string
	Client *http.Client

	endpointOverride string
}

func (p *Purger) Configured() bool {
	return p != nil && p.ZoneID != "" && p.Token != "" && len(p.URLs) > 0
}

func (p *Purger) client() *http.Client {
	if p.Client != nil {
		return p.Client
	}
	return &http.Client{Timeout: 10 * time.Second}
}

func (p *Purger) Purge(ctx context.Context, extra ...string) error {
	if !p.Configured() {
		return nil
	}
	files := append(append([]string{}, p.URLs...), extra...)
	payload, err := json.Marshal(map[string]any{"files": files})
	if err != nil {
		return err
	}
	endpoint := "https://api.cloudflare.com/client/v4/zones/" + p.ZoneID + "/purge_cache"
	if p.endpointOverride != "" {
		endpoint = p.endpointOverride
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+p.Token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("cloudflare purge failed (%d): %s", resp.StatusCode, bytes.TrimSpace(body))
	}
	return nil
}
