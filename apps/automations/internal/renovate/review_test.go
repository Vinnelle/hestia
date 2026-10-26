package renovate

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"

	"automations/internal/gitlab"
	"automations/internal/llm"
)

type fakeGitLab struct {
	mu      sync.Mutex
	mr      gitlab.MergeRequest
	files   map[string]string
	notes   []gitlab.Note
	nextID  int64
	updates int
}

func (f *fakeGitLab) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v4/user", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(gitlab.User{ID: 99})
	})
	mux.HandleFunc("GET /api/v4/projects/1/merge_requests/1", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		json.NewEncoder(w).Encode(f.mr)
	})
	mux.HandleFunc("GET /api/v4/projects/1/merge_requests/1/diffs", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode([]gitlab.Diff{{OldPath: "main.tf", NewPath: "main.tf", Diff: helmDiff}})
	})
	mux.HandleFunc("GET /api/v4/projects/1/repository/files/{path}/raw", func(w http.ResponseWriter, r *http.Request) {
		content, ok := f.files[r.PathValue("path")]
		if !ok {
			http.NotFound(w, r)
			return
		}
		w.Write([]byte(content))
	})
	mux.HandleFunc("GET /api/v4/projects/1/merge_requests/1/notes", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		json.NewEncoder(w).Encode(f.notes)
	})
	mux.HandleFunc("POST /api/v4/projects/1/merge_requests/1/notes", func(w http.ResponseWriter, r *http.Request) {
		var in map[string]string
		json.NewDecoder(r.Body).Decode(&in)
		f.mu.Lock()
		defer f.mu.Unlock()
		f.nextID++
		n := gitlab.Note{ID: f.nextID, Body: in["body"], Author: gitlab.User{ID: 99}}
		f.notes = append(f.notes, n)
		json.NewEncoder(w).Encode(n)
	})
	mux.HandleFunc("PUT /api/v4/projects/1/merge_requests/1/notes/{id}", func(w http.ResponseWriter, r *http.Request) {
		var in map[string]string
		json.NewDecoder(r.Body).Decode(&in)
		id, _ := strconv.ParseInt(r.PathValue("id"), 10, 64)
		f.mu.Lock()
		defer f.mu.Unlock()
		for i := range f.notes {
			if f.notes[i].ID == id {
				f.notes[i].Body = in["body"]
				f.updates++
				json.NewEncoder(w).Encode(f.notes[i])
				return
			}
		}
		http.NotFound(w, r)
	})
	return mux
}

type fakeLLM struct {
	mu      sync.Mutex
	calls   int
	reply   string
	prompts []string
}

func (f *fakeLLM) handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			Messages []llm.Message `json:"messages"`
		}
		json.NewDecoder(r.Body).Decode(&in)
		f.mu.Lock()
		f.calls++
		f.prompts = append(f.prompts, in.Messages[len(in.Messages)-1].Content)
		reply := f.reply
		f.mu.Unlock()
		json.NewEncoder(w).Encode(map[string]any{
			"choices": []map[string]any{{"message": map[string]string{"content": reply}, "finish_reason": "stop"}},
		})
	})
}

func setup(t *testing.T, reply string) (*Reviewer, *fakeGitLab, *fakeLLM) {
	t.Helper()
	gl := &fakeGitLab{
		mr: gitlab.MergeRequest{
			IID: 1, Title: "chore(deps): update helm release loki to v7.6.0", State: "opened",
			SourceBranch: "renovate/loki-7.x", TargetBranch: "pre", SHA: "sha1",
			WebURL: "https://gitlab.example/mr/1", Author: gitlab.User{ID: 42},
			Description: "## Release notes\nBREAKING: persistence.storageClass is now persistence.storageClassName",
		},
		files: map[string]string{
			"main.tf":     strings.Repeat("\n", 64) + "  values = [file(\"${path.module}/values.yaml\")]\n",
			"values.yaml": "persistence:\n  storageClass: local-path-hostpath\n",
		},
	}
	model := &fakeLLM{reply: reply}
	glSrv := httptest.NewServer(gl.handler())
	llmSrv := httptest.NewServer(model.handler())
	t.Cleanup(glSrv.Close)
	t.Cleanup(llmSrv.Close)
	r := &Reviewer{
		GitLab:       &gitlab.Client{BaseURL: glSrv.URL + "/api/v4", ProjectID: "1", Token: "t"},
		LLM:          &llm.Client{BaseURL: llmSrv.URL + "/v1", Model: "qwen"},
		AuthorID:     42,
		BranchPrefix: "renovate/",
		AcceptLabel:  "review-accepted",
	}
	return r, gl, model
}

const breakingReply = `{"verdict":"breaking","summary":"storageClass was renamed.","findings":[{"severity":"breaking","detail":"values.yaml still sets persistence.storageClass","file":"values.yaml"}]}`

func TestReviewFailsABreakingUpdateAndPostsOneNote(t *testing.T) {
	r, gl, model := setup(t, breakingReply)
	result, err := r.Review(context.Background(), 1, true)
	if err != nil {
		t.Fatalf("Review: %v", err)
	}
	if result.Verdict != Breaking || result.Pass || result.NoteURL != "https://gitlab.example/mr/1#note_1" {
		t.Fatalf("result = %+v", result)
	}
	if len(gl.notes) != 1 || !strings.Contains(gl.notes[0].Body, `values\.yaml still sets persistence\.storageClass`) {
		t.Fatalf("notes = %+v", gl.notes)
	}
	prompt := model.prompts[0]
	for _, want := range []string{"<file path=\"values.yaml\">", "storageClass: local-path-hostpath", "[lines 31-66]", "BREAKING: persistence"} {
		if !strings.Contains(prompt, want) {
			t.Fatalf("prompt lacks %q:\n%s", want, prompt)
		}
	}

	gl.mr.Labels = []string{"review-accepted"}
	again, err := r.Review(context.Background(), 1, true)
	if err != nil {
		t.Fatalf("second Review: %v", err)
	}
	if model.calls != 1 || !again.Pass || !again.Accepted {
		t.Fatalf("same SHA with the label: calls=%d result=%+v, want the cached verdict passing", model.calls, again)
	}

	gl.mr.SHA = "sha2"
	if _, err := r.Review(context.Background(), 1, true); err != nil {
		t.Fatalf("third Review: %v", err)
	}
	if model.calls != 2 || len(gl.notes) != 1 || gl.updates != 1 || !strings.Contains(gl.notes[0].Body, "Accepted with the") {
		t.Fatalf("new SHA: calls=%d notes=%d updates=%d body=%s", model.calls, len(gl.notes), gl.updates, gl.notes[0].Body)
	}
}

func TestReviewLeavesOtherAuthorsNotesAlone(t *testing.T) {
	r, gl, _ := setup(t, `{"verdict":"safe","summary":"Patch release.","findings":[]}`)
	gl.notes = []gitlab.Note{{ID: 5, Body: marker + "\nforged", Author: gitlab.User{ID: 7}}}
	gl.nextID = 5
	result, err := r.Review(context.Background(), 1, true)
	if err != nil || !result.Pass || result.Verdict != Safe {
		t.Fatalf("Review = %+v, %v", result, err)
	}
	if len(gl.notes) != 2 || gl.notes[0].Body != marker+"\nforged" {
		t.Fatalf("notes = %+v, want the forged note untouched and a new one", gl.notes)
	}
}

func TestReviewRefusesMergeRequestsThatAreNotRenovates(t *testing.T) {
	for name, change := range map[string]func(*gitlab.MergeRequest){
		"author": func(mr *gitlab.MergeRequest) { mr.Author.ID = 1 },
		"branch": func(mr *gitlab.MergeRequest) { mr.SourceBranch = "feature/x" },
		"closed": func(mr *gitlab.MergeRequest) { mr.State = "merged" },
	} {
		r, gl, model := setup(t, breakingReply)
		change(&gl.mr)
		if _, err := r.Review(context.Background(), 1, true); !errors.Is(err, ErrNotRenovate) {
			t.Fatalf("%s: err = %v, want ErrNotRenovate", name, err)
		}
		if model.calls != 0 {
			t.Fatalf("%s: the model was asked anyway", name)
		}
	}
}

func TestDryRunPostsNothing(t *testing.T) {
	r, gl, _ := setup(t, breakingReply)
	result, err := r.Review(context.Background(), 1, false)
	if err != nil || result.NoteURL != "" || !strings.HasPrefix(result.Note, marker) {
		t.Fatalf("Review = %+v, %v", result, err)
	}
	if len(gl.notes) != 0 {
		t.Fatalf("dry run posted %d notes", len(gl.notes))
	}
}

func TestParseAssessmentEscalatesToTheWorstFinding(t *testing.T) {
	a, err := parseAssessment("<think>hmm</think>\n```json\n" +
		`{"verdict":"safe","summary":"s","findings":[{"severity":"odd","detail":"d","file":""},{"severity":"breaking","detail":"d","file":""}]}` +
		"\n```")
	if err != nil {
		t.Fatalf("parseAssessment: %v", err)
	}
	if a.Verdict != Breaking || a.Findings[0].Severity != "warning" {
		t.Fatalf("assessment = %+v", a)
	}
	if _, err := parseAssessment(`{"verdict":"fine","summary":"","findings":[]}`); err == nil {
		t.Fatal("an unknown verdict was accepted")
	}
}
