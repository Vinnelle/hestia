package llm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestAsk(t *testing.T) {
	var got request
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer key" {
			http.Error(w, "unexpected request", http.StatusBadRequest)
			return
		}
		json.NewDecoder(r.Body).Decode(&got)
		w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"<think>hmm</think> hi @bob"}}],` +
			`"usage":{"prompt_tokens":1913,"completion_tokens":62},"timings":{"cache_n":1700,"prompt_n":213,"predicted_n":62}}`))
	}))
	defer srv.Close()

	c := &Client{BaseURL: srv.URL + "/v1/", Model: "m", APIKey: "key", Temperature: 0.7}
	reply, use, err := c.Ask(context.Background(), []Message{{Role: "user", Content: "bob: hello"}}, nil, 64)
	if err != nil {
		t.Fatal(err)
	}
	if reply != "hi @bob" {
		t.Errorf("reply = %q", reply)
	}
	if use.Cached != 1700 || use.New != 213 || use.Out != 62 || use.Took <= 0 {
		t.Errorf("usage = %+v", use)
	}
	if got.Model != "m" || got.MaxTokens != 64 || got.Stream || got.ChatTemplateKwargs["enable_thinking"] || got.ResponseFormat != nil {
		t.Errorf("request = %+v", got)
	}

	if _, _, err := c.Ask(context.Background(), nil, json.RawMessage(`{"type":"object"}`), 300); err != nil {
		t.Fatal(err)
	}
	if got.ResponseFormat == nil || got.ResponseFormat.Type != "json_schema" || !got.ResponseFormat.JSONSchema.Strict ||
		string(got.ResponseFormat.JSONSchema.Schema) != `{"type":"object"}` || got.MaxTokens != 300 {
		t.Errorf("request with a schema = %+v", got)
	}
}

func TestUsage(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"choices":[{"message":{"content":"hi"}}],"usage":{"prompt_tokens":2400,"completion_tokens":9,"prompt_tokens_details":{"cached_tokens":2048}}}`))
	}))
	defer srv.Close()
	_, use, err := (&Client{BaseURL: srv.URL}).Ask(context.Background(), nil, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	use.Took = 4840 * time.Millisecond
	if got := use.String(); got != "4.8s; tokens: 2.0k cached, 352 new, 9 out" {
		t.Errorf("usage = %q", got)
	}
	if got := (Usage{Took: time.Second}).String(); got != "1s" {
		t.Errorf("usage without tokens = %q", got)
	}
}

func TestAskRejectsEmptyAndFailedReplies(t *testing.T) {
	for _, body := range []string{
		`{"choices":[{"message":{"role":"assistant","content":"<think>never finished"}}]}`,
		`{"choices":[]}`,
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte(body))
		}))
		if _, _, err := (&Client{BaseURL: srv.URL}).Ask(context.Background(), nil, nil, 0); err == nil {
			t.Errorf("no error for %s", body)
		}
		srv.Close()
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "busy", http.StatusServiceUnavailable)
	}))
	defer srv.Close()
	if _, _, err := (&Client{BaseURL: srv.URL}).Ask(context.Background(), nil, nil, 0); err == nil {
		t.Error("no error for a 503")
	}
}
