package digest

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"automations/internal/gitlab"
	"automations/internal/kube"
	"automations/internal/llm"
	"automations/internal/prom"
)

func sampleFacts() Facts {
	to := time.Date(2026, 10, 26, 6, 0, 0, 0, time.UTC)
	return Facts{
		From: to.Add(-24 * time.Hour),
		To:   to,
		Cluster: Cluster{
			Ready: true, Talos: "v1.14.4", Kubernetes: "v1.37.1", Kernel: "6.18.57-talos",
			CPU:         Usage{Used: 0.6, Peak: 8.6, Total: 12},
			Memory:      Usage{Used: 13 << 30, Peak: 21 << 30, Total: 24 << 30},
			Filesystems: []Filesystem{{Mount: "/var", Used: 85, Size: 100}},
			PodsRunning: 60, PodsTotal: 61,
			PodIssues: []PodIssue{{Namespace: "llm", Pod: "llm-0", Reason: "CrashLoopBackOff"}},
			Restarts:  []Restart{{Namespace: "observability", Pod: "loki-0", Count: 7}},
		},
		Traffic: Traffic{Requests: 87000, PreviousRequests: 89000, ServerErrors: 1400, Hosts: []Host{{Host: "gitlab.vinnel.cloud", Requests: 62000, Errors: 3, Bytes: 9 << 30}}},
		Alerts:  []Alert{{Name: "KubePodNotReady", Severity: "warning", Namespace: "llm", Firing: true}},
		Changes: Changes{
			Commits: []Commit{{SHA: "abc1234", Title: "feat: <b>bold</b> move", Author: "ida", URL: "https://gitlab.vinnel.cloud/c/abc"}},
			Merged:  []Merge{{IID: 4, Title: "chore(deps): loki", Renovate: true}},
			Images:  []ImageChange{{Workload: "llm/deployment/llm", From: "llama.cpp:b1", To: "llama.cpp:b2"}},
			Reviews: map[string]int{"breaking": 1},
		},
		Security:     Security{Critical: 3, High: 10, PrevCritical: 2, PrevHigh: 10, Known: true},
		Certificates: []Certificate{{Name: "gitlab-tls", Namespace: "forge", Days: 12, Ready: true}},
	}
}

func TestChecksFindWhatNeedsAttention(t *testing.T) {
	checks := Checks(sampleFacts())
	var texts []string
	for _, c := range checks {
		texts = append(texts, c.Severity+": "+c.Text)
	}
	joined := strings.Join(texts, "\n")
	for _, want := range []string{
		"warning: Alert KubePodNotReady is firing in llm.",
		"warning: Pod llm/llm-0 is CrashLoopBackOff.",
		"warning: /var is 85% full.",
		"warning: observability/loki-0 restarted 7 times.",
		"warning: Certificate forge/gitlab-tls expires in 12 days.",
		"warning: Critical vulnerabilities rose from 2 to 3.",
		"info: The Renovate reviewer held back 1 update(s) as breaking.",
	} {
		if !strings.Contains(joined, want) {
			t.Fatalf("checks lack %q:\n%s", want, joined)
		}
	}
	if Floor(checks) != Attention {
		t.Fatalf("floor = %s, want attention", Floor(checks))
	}
	f := sampleFacts()
	f.Cluster.Ready = false
	if Floor(Checks(f)) != Action {
		t.Fatal("a node that is not Ready did not call for action")
	}
}

func llmServer(t *testing.T, reply string) *llm.Client {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"choices": []map[string]any{{"message": map[string]string{"content": reply}, "finish_reason": "stop"}}})
	}))
	t.Cleanup(srv.Close)
	return &llm.Client{BaseURL: srv.URL, Model: "gemma"}
}

func TestSummarizeNeverGoesBelowTheFloor(t *testing.T) {
	checks := []Concern{{Severity: "critical", Text: "node down"}}
	s, err := Summarize(context.Background(), llmServer(t, `<think>x</think>{"status":"healthy","headline":"Fine","summary":"ok","concerns":[{"severity":"odd","text":"t"},{"severity":"info","text":" "}],"suggestions":["a","b","c","d"]}`), sampleFacts(), checks)
	if err != nil {
		t.Fatalf("Summarize: %v", err)
	}
	if s.Status != Action || len(s.Concerns) != 1 || s.Concerns[0].Severity != "info" || len(s.Suggestions) != 3 || s.Model != "gemma" {
		t.Fatalf("summary = %+v", s)
	}
	if _, err := Summarize(context.Background(), llmServer(t, "not json"), sampleFacts(), nil); err == nil {
		t.Fatal("a non-JSON reply was accepted")
	}
}

func TestRenderEscapesAndStaysSmall(t *testing.T) {
	f := sampleFacts()
	s := Summary{Status: Attention, Headline: "Mostly <script>alert(1)</script> fine", Summary: "Traffic & things.", Suggestions: []string{"Look at <img src=x>"}, Model: "gemma"}
	v := Build(f, s, Checks(f), time.UTC, "https://admin.vinnel.cloud")
	html, err := Render(v)
	if err != nil {
		t.Fatalf("Render: %v", err)
	}
	for _, raw := range []string{"<script>", "<img src=x>", "<b>bold</b>"} {
		if strings.Contains(html, raw) {
			t.Fatalf("html keeps %q unescaped", raw)
		}
	}
	for _, want := range []string{"Needs attention", "gitlab.vinnel.cloud", "llama.cpp:b1", "Monday 26 October", "Renovate reviews: 1 breaking", "https://gitlab.vinnel.cloud/c/abc"} {
		if !strings.Contains(html, want) {
			t.Fatalf("html lacks %q", want)
		}
	}
	if len(html) > 90_000 {
		t.Fatalf("html is %d bytes; Gmail clips messages over about 100 kB", len(html))
	}
	if subject := Subject(s, f.To); subject != "hestia · Mon 26 Oct · Needs attention" {
		t.Fatalf("subject = %q", subject)
	}
	if text := Text(v); !strings.Contains(text, "NEEDS ATTENTION") || !strings.Contains(text, "feat: <b>bold</b> move") {
		t.Fatalf("text = %s", text)
	}
}

type fakeKube struct {
	mu   sync.Mutex
	data map[string]string
	puts int
}

func (f *fakeKube) server(t *testing.T) *kube.Client {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer token" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		f.mu.Lock()
		defer f.mu.Unlock()
		switch {
		case r.URL.Path == "/api/v1/namespaces/automations/configmaps/digest-state" && r.Method == http.MethodGet:
			json.NewEncoder(w).Encode(map[string]any{"apiVersion": "v1", "kind": "ConfigMap", "metadata": map[string]any{"name": "digest-state", "resourceVersion": "7"}, "data": f.data})
		case r.URL.Path == "/api/v1/namespaces/automations/configmaps/digest-state" && r.Method == http.MethodPut:
			var cm configMap
			json.NewDecoder(r.Body).Decode(&cm)
			if cm.Metadata["resourceVersion"] != "7" {
				http.Error(w, "conflict", http.StatusConflict)
				return
			}
			f.data = cm.Data
			f.puts++
			json.NewEncoder(w).Encode(cm)
		case strings.HasPrefix(r.URL.Path, "/apis/apps/v1/"):
			kind := strings.TrimPrefix(r.URL.Path, "/apis/apps/v1/")
			items := []any{}
			if kind == "deployments" {
				items = append(items, map[string]any{
					"metadata": map[string]any{"namespace": "llm", "name": "llm"},
					"spec":     map[string]any{"template": map[string]any{"spec": map[string]any{"containers": []any{map[string]any{"image": "ghcr.io/ggml-org/llama.cpp:b2@sha256:" + strings.Repeat("a", 64)}}}}},
				})
			}
			json.NewEncoder(w).Encode(map[string]any{"items": items})
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return &kube.Client{BaseURL: srv.URL, Token: "token", HTTP: srv.Client()}
}

func TestRunSendsOnceAndMovesTheWindow(t *testing.T) {
	sent := time.Date(2026, 10, 25, 6, 0, 0, 0, time.UTC)
	prev, _ := json.Marshal(Snapshot{SentAt: sent, Images: map[string][]string{"llm/deployment/llm": {"ghcr.io/ggml-org/llama.cpp:b1"}}, Critical: 2})
	fk := &fakeKube{data: map[string]string{stateKey: string(prev)}}
	client := fk.server(t)

	var queries []string
	var qmu sync.Mutex
	vm := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("query")
		qmu.Lock()
		queries = append(queries, q)
		qmu.Unlock()
		result := `[]`
		switch {
		case strings.HasPrefix(q, "max(kube_node_status_condition"):
			result = `[{"metric":{},"value":[0,"1"]}]`
		case strings.HasPrefix(q, "sum by (severity)"):
			result = `[{"metric":{"severity":"Critical"},"value":[0,"3"]}]`
		}
		w.Write([]byte(`{"status":"success","data":{"resultType":"vector","result":` + result + `}}`))
	}))
	defer vm.Close()

	var mail struct {
		Email
		Key string
	}
	resend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		json.Unmarshal(body, &mail.Email)
		mail.Key = r.Header.Get("Idempotency-Key")
		if r.Header.Get("Authorization") != "Bearer re_key" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		w.Write([]byte(`{"id":"email-1"}`))
	}))
	defer resend.Close()

	gl := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/repository/commits"):
			if r.URL.Query().Get("since") != sent.Format(time.RFC3339) || r.URL.Query().Get("ref_name") != "prd" {
				http.Error(w, "bad since", http.StatusBadRequest)
				return
			}
			json.NewEncoder(w).Encode([]gitlab.Commit{{ShortID: "abc", Title: "feat: x"}, {ShortID: "def", Title: "deploy: pin llm image digest [skip ci]"}})
		default:
			w.Write([]byte(`[]`))
		}
	}))
	defer gl.Close()

	now := time.Date(2026, 10, 26, 6, 0, 30, 0, time.UTC)
	d := &Digest{
		Collector: &Collector{
			Prom:           &prom.Client{BaseURL: vm.URL},
			Kube:           client,
			GitLab:         &gitlab.Client{BaseURL: gl.URL, ProjectID: "1", Token: "t"},
			DefaultBranch:  "prd",
			RenovatePrefix: "renovate/",
		},
		LLM:      llmServer(t, `{"status":"healthy","headline":"Quiet day","summary":"Nothing much.","concerns":[],"suggestions":[]}`),
		State:    &State{Kube: client, Namespace: "automations", Name: "digest-state"},
		Mailer:   &Resend{APIKey: "re_key", BaseURL: resend.URL},
		From:     "hestia <digest@vinnel.cloud>",
		To:       []string{"me@example.org"},
		Location: time.UTC,
		Job:      "digest-29877120",
		Now:      func() time.Time { return now },
	}
	if err := d.Run(context.Background()); err != nil {
		t.Fatalf("Run: %v", err)
	}

	if mail.Key != "digest-29877120" || mail.To[0] != "me@example.org" || mail.Subject != "hestia · Mon 26 Oct · Needs attention" {
		t.Fatalf("mail = %+v", mail)
	}
	for _, want := range []string{"feat: x", "1 image pin by CI", "llama.cpp:b1", "was 2 critical"} {
		if !strings.Contains(mail.HTML, want) {
			t.Fatalf("mail lacks %q", want)
		}
	}
	var window bool
	for _, q := range queries {
		if strings.Contains(q, "[86400s]") {
			window = true
		}
	}
	if !window {
		t.Fatalf("no query used the 24 h window since the last digest: %v", queries[:3])
	}

	var saved Snapshot
	json.Unmarshal([]byte(fk.data[stateKey]), &saved)
	if fk.puts != 1 || !saved.SentAt.Equal(now.Truncate(time.Minute)) || saved.Critical != 3 || saved.Images["llm/deployment/llm"] == nil {
		t.Fatalf("saved state = %+v (puts %d)", saved, fk.puts)
	}
}

func TestResendReportsErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"message":"invalid from"}`, http.StatusUnprocessableEntity)
	}))
	defer srv.Close()
	_, err := (&Resend{APIKey: "k", BaseURL: srv.URL}).Send(context.Background(), Email{To: []string{"a@b"}}, "")
	if err == nil || !strings.Contains(err.Error(), "422") {
		t.Fatalf("err = %v", err)
	}
}

func TestPublicHostsDropInternalNames(t *testing.T) {
	q := url.QueryEscape(publicHosts)
	if !strings.Contains(publicHosts, `\\.internal`) || q == "" {
		t.Fatalf("publicHosts = %s", publicHosts)
	}
}
