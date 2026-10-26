package llm

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func server(t *testing.T, finish string, seen *request) *Client {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer key" {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		json.NewDecoder(r.Body).Decode(seen)
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{{
				"message":       map[string]string{"role": "assistant", "content": ` {"ok":true} `},
				"finish_reason": finish,
			}},
		})
	}))
	t.Cleanup(srv.Close)
	return &Client{BaseURL: srv.URL + "/v1/", Model: "m", APIKey: "key"}
}

func TestCompleteSendsTheSchemaAndReturnsTheContent(t *testing.T) {
	var seen request
	c := server(t, "stop", &seen)
	out, err := c.Complete(context.Background(), "review", json.RawMessage(`{"type":"object"}`), Message{Role: "user", Content: "hi"})
	if err != nil || out != `{"ok":true}` {
		t.Fatalf("Complete = %q, %v", out, err)
	}
	if seen.Model != "m" || seen.Temperature != 0 || seen.Stream || len(seen.Messages) != 1 {
		t.Fatalf("request = %+v", seen)
	}
	if seen.ResponseFormat == nil || seen.ResponseFormat.Type != "json_schema" || !seen.ResponseFormat.JSONSchema.Strict || seen.ResponseFormat.JSONSchema.Name != "review" {
		t.Fatalf("response_format = %+v", seen.ResponseFormat)
	}
}

func TestCompleteRejectsATruncatedReply(t *testing.T) {
	var seen request
	if _, err := server(t, "length", &seen).Complete(context.Background(), "review", nil); !errors.Is(err, ErrTruncated) {
		t.Fatalf("err = %v, want ErrTruncated", err)
	}
	if seen.ResponseFormat != nil {
		t.Fatalf("response_format sent without a schema: %+v", seen.ResponseFormat)
	}
}
