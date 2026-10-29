package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type Client struct {
	BaseURL     string
	Model       string
	APIKey      string
	Temperature float64
	HTTP        *http.Client
}

type jsonSchema struct {
	Name   string          `json:"name"`
	Strict bool            `json:"strict"`
	Schema json.RawMessage `json:"schema"`
}

type responseFormat struct {
	Type       string     `json:"type"`
	JSONSchema jsonSchema `json:"json_schema"`
}

type request struct {
	Model              string          `json:"model"`
	Messages           []Message       `json:"messages"`
	Temperature        float64         `json:"temperature"`
	MaxTokens          int             `json:"max_tokens,omitempty"`
	Stream             bool            `json:"stream"`
	ChatTemplateKwargs map[string]bool `json:"chat_template_kwargs"`
	ResponseFormat     *responseFormat `json:"response_format,omitempty"`
}

type response struct {
	Choices []struct {
		Message Message `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		Details          *struct {
			CachedTokens int `json:"cached_tokens"`
		} `json:"prompt_tokens_details"`
	} `json:"usage"`
	Timings *struct {
		CacheN     int `json:"cache_n"`
		PromptN    int `json:"prompt_n"`
		PredictedN int `json:"predicted_n"`
	} `json:"timings"`
}

type Usage struct {
	Cached int
	New    int
	Out    int
	Took   time.Duration
}

func (u Usage) String() string {
	s := u.Took.Round(100 * time.Millisecond).String()
	if u.Cached+u.New+u.Out > 0 {
		s += fmt.Sprintf("; tokens: %s cached, %s new, %s out", count(u.Cached), count(u.New), count(u.Out))
	}
	return s
}

func count(n int) string {
	if n < 1000 {
		return fmt.Sprint(n)
	}
	return fmt.Sprintf("%.1fk", float64(n)/1000)
}

var thought = regexp.MustCompile(`(?s)<think>.*?</think>`)

func (c *Client) client() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 5 * time.Minute}
}

func (c *Client) Ask(ctx context.Context, messages []Message, schema json.RawMessage, maxTokens int) (string, Usage, error) {
	in := request{
		Model:              c.Model,
		Messages:           messages,
		Temperature:        c.Temperature,
		MaxTokens:          maxTokens,
		ChatTemplateKwargs: map[string]bool{"enable_thinking": false},
	}
	if schema != nil {
		in.ResponseFormat = &responseFormat{Type: "json_schema", JSONSchema: jsonSchema{Name: "replies", Strict: true, Schema: schema}}
	}
	payload, err := json.Marshal(in)
	if err != nil {
		return "", Usage{}, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(c.BaseURL, "/")+"/chat/completions", bytes.NewReader(payload))
	if err != nil {
		return "", Usage{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	start := time.Now()
	resp, err := c.client().Do(req)
	if err != nil {
		return "", Usage{}, fmt.Errorf("llm: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", Usage{}, fmt.Errorf("llm: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body := strings.TrimSpace(string(data))
		if len(body) > 200 {
			body = body[:200] + "..."
		}
		return "", Usage{}, fmt.Errorf("llm: %d %s", resp.StatusCode, body)
	}
	var out response
	if err := json.Unmarshal(data, &out); err != nil {
		return "", Usage{}, fmt.Errorf("llm: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", Usage{}, errors.New("llm: reply has no choices")
	}
	use := Usage{New: out.Usage.PromptTokens, Out: out.Usage.CompletionTokens, Took: time.Since(start)}
	if d := out.Usage.Details; d != nil {
		use.Cached, use.New = d.CachedTokens, use.New-d.CachedTokens
	}
	if t := out.Timings; t != nil {
		use.Cached, use.New, use.Out = t.CacheN, t.PromptN, t.PredictedN
	}
	content := thought.ReplaceAllString(out.Choices[0].Message.Content, "")
	if i := strings.Index(content, "<think>"); i >= 0 {
		content = content[:i]
	}
	content = strings.TrimSpace(content)
	if content == "" {
		return "", use, errors.New("llm: empty reply")
	}
	return content, use, nil
}
