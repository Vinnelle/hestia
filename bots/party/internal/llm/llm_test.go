package llm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAsk(t *testing.T) {
	var got request
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" || r.Header.Get("Authorization") != "Bearer key" {
			http.Error(w, "unexpected request", http.StatusBadRequest)
			return
		}
		json.NewDecoder(r.Body).Decode(&got)
		w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"<think>hmm</think> hi @bob"}}]}`))
	}))
	defer srv.Close()

	c := &Client{BaseURL: srv.URL + "/v1/", Model: "m", APIKey: "key", MaxTokens: 64, Temperature: 0.7}
	reply, err := c.Ask(context.Background(), []Message{{Role: "user", Content: "bob: hello"}})
	if err != nil {
		t.Fatal(err)
	}
	if reply != "hi @bob" {
		t.Errorf("reply = %q", reply)
	}
	if got.Model != "m" || got.MaxTokens != 64 || got.Stream || got.ChatTemplateKwargs["enable_thinking"] {
		t.Errorf("request = %+v", got)
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
		if _, err := (&Client{BaseURL: srv.URL}).Ask(context.Background(), nil); err == nil {
			t.Errorf("no error for %s", body)
		}
		srv.Close()
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "busy", http.StatusServiceUnavailable)
	}))
	defer srv.Close()
	if _, err := (&Client{BaseURL: srv.URL}).Ask(context.Background(), nil); err == nil {
		t.Error("no error for a 503")
	}
}
