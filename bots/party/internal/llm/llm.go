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
}

var thought = regexp.MustCompile(`(?s)<think>.*?</think>`)

func (c *Client) client() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	return &http.Client{Timeout: 5 * time.Minute}
}

func (c *Client) Ask(ctx context.Context, messages []Message, schema json.RawMessage, maxTokens int) (string, error) {
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
		return "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(c.BaseURL, "/")+"/chat/completions", bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.APIKey)
	}
	resp, err := c.client().Do(req)
	if err != nil {
		return "", fmt.Errorf("llm: %w", err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", fmt.Errorf("llm: %w", err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body := strings.TrimSpace(string(data))
		if len(body) > 200 {
			body = body[:200] + "..."
		}
		return "", fmt.Errorf("llm: %d %s", resp.StatusCode, body)
	}
	var out response
	if err := json.Unmarshal(data, &out); err != nil {
		return "", fmt.Errorf("llm: %w", err)
	}
	if len(out.Choices) == 0 {
		return "", errors.New("llm: reply has no choices")
	}
	content := thought.ReplaceAllString(out.Choices[0].Message.Content, "")
	if i := strings.Index(content, "<think>"); i >= 0 {
		content = content[:i]
	}
	content = strings.TrimSpace(content)
	if content == "" {
		return "", errors.New("llm: empty reply")
	}
	return content, nil
}
