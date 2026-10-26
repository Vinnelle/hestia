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
	out, err := c.Complete(context.Background(), "review", json.RawMessage(`{"type":"object"}`), 0, Message{Role: "user", Content: "hi"})
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
	if _, err := server(t, "length", &seen).Complete(context.Background(), "review", nil, 0); !errors.Is(err, ErrTruncated) {
		t.Fatalf("err = %v, want ErrTruncated", err)
	}
	if seen.ResponseFormat != nil {
		t.Fatalf("response_format sent without a schema: %+v", seen.ResponseFormat)
	}
}

func TestAskRetriesOnceWithSampling(t *testing.T) {
	var temps []float64
	var maxTokens []int
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var in request
		json.NewDecoder(r.Body).Decode(&in)
		temps = append(temps, in.Temperature)
		maxTokens = append(maxTokens, in.MaxTokens)
		finish := "length"
		if len(temps) == 2 {
			finish = "stop"
		}
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{{"message": map[string]string{"content": "ok"}, "finish_reason": finish}},
		})
	}))
	defer srv.Close()
	c := &Client{BaseURL: srv.URL, Model: "m", MaxTokens: 8192}

	var got string
	err := c.Ask(context.Background(), "review", nil, func(reply string) error { got = reply; return nil }, Message{Role: "user", Content: "hi"})
	if err != nil || got != "ok" {
		t.Fatalf("Ask = %q, %v", got, err)
	}
	if len(temps) != 2 || temps[0] != 0 || temps[1] != 0.7 || maxTokens[0] != 8192 {
		t.Fatalf("temperatures %v, max tokens %v", temps, maxTokens)
	}

	temps = nil
	calls := 0
	err = c.Ask(context.Background(), "review", nil, func(string) error { calls++; return errors.New("not JSON") }, Message{Role: "user", Content: "hi"})
	if err == nil || err.Error() != "not JSON" || len(temps) != 2 || calls != 1 {
		t.Fatalf("Ask with a rejected reply = %v after %d requests and %d accepted replies", err, len(temps), calls)
	}
}
