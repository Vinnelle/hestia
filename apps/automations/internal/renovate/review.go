package renovate

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"

	"automations/internal/gitlab"
	"automations/internal/llm"
)

var ErrNotRenovate = errors.New("not an open Renovate merge request")

type Verdict string

const (
	Safe     Verdict = "safe"
	Check    Verdict = "check"
	Breaking Verdict = "breaking"
)

var rank = map[Verdict]int{Safe: 0, Check: 1, Breaking: 2}

var severities = map[string]Verdict{"info": Safe, "warning": Check, "breaking": Breaking}

const (
	maxFindings = 8
	maxCached   = 256
)

type Finding struct {
	Severity string `json:"severity"`
	Detail   string `json:"detail"`
	File     string `json:"file"`
}

type Assessment struct {
	Verdict  Verdict   `json:"verdict"`
	Summary  string    `json:"summary"`
	Findings []Finding `json:"findings"`
}

type Result struct {
	MergeRequest int64   `json:"merge_request_iid"`
	SHA          string  `json:"sha"`
	Verdict      Verdict `json:"verdict"`
	Accepted     bool    `json:"accepted"`
	Pass         bool    `json:"pass"`
	Cached       bool    `json:"cached"`
	NoteURL      string  `json:"note_url,omitempty"`
	Note         string  `json:"-"`
}

var schema = json.RawMessage(`{
  "type": "object",
  "additionalProperties": false,
  "required": ["verdict", "summary", "findings"],
  "properties": {
    "verdict": {"type": "string", "enum": ["safe", "check", "breaking"]},
    "summary": {"type": "string", "maxLength": 600},
    "findings": {
      "type": "array",
      "maxItems": 8,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["severity", "detail", "file"],
        "properties": {
          "severity": {"type": "string", "enum": ["info", "warning", "breaking"]},
          "detail": {"type": "string", "maxLength": 400},
          "file": {"type": "string", "maxLength": 200}
        }
      }
    }
  }
}`)

type Reviewer struct {
	GitLab       *gitlab.Client
	LLM          *llm.Client
	AuthorID     int64
	BranchPrefix string
	AcceptLabel  string
	MaxPrompt    int

	once   sync.Once
	turn   chan struct{}
	cache  map[string]Result
	selfID int64
}

func pass(v Verdict, accepted bool) bool {
	return accepted || v != Breaking
}

func (r *Reviewer) Review(ctx context.Context, iid int64, post bool) (Result, error) {
	r.once.Do(func() {
		r.turn = make(chan struct{}, 1)
		r.cache = map[string]Result{}
	})
	select {
	case r.turn <- struct{}{}:
	case <-ctx.Done():
		return Result{}, ctx.Err()
	}
	defer func() { <-r.turn }()

	mr, err := r.GitLab.MergeRequest(ctx, iid)
	if err != nil {
		return Result{}, err
	}
	if mr.State != "opened" || r.BranchPrefix == "" || !strings.HasPrefix(mr.SourceBranch, r.BranchPrefix) || (r.AuthorID != 0 && mr.Author.ID != r.AuthorID) {
		return Result{}, fmt.Errorf("%w: !%d", ErrNotRenovate, iid)
	}
	accepted := r.AcceptLabel != "" && slices.Contains(mr.Labels, r.AcceptLabel)

	if cached, ok := r.cache[mr.SHA]; ok && post {
		cached.Accepted = accepted
		cached.Pass = pass(cached.Verdict, accepted)
		cached.Cached = true
		return cached, nil
	}

	diffs, err := r.GitLab.Diffs(ctx, iid)
	if err != nil {
		return Result{}, err
	}
	files, err := r.contextFiles(ctx, mr.SHA, diffs)
	if err != nil {
		return Result{}, err
	}
	var a Assessment
	err = r.LLM.Ask(ctx, "renovate_review", schema, func(reply string) error {
		var err error
		a, err = parseAssessment(reply)
		return err
	},
		llm.Message{Role: "system", Content: systemPrompt},
		llm.Message{Role: "user", Content: buildPrompt(mr, diffs, files, r.MaxPrompt)},
	)
	if err != nil {
		return Result{}, err
	}

	result := Result{
		MergeRequest: iid,
		SHA:          mr.SHA,
		Verdict:      a.Verdict,
		Accepted:     accepted,
		Pass:         pass(a.Verdict, accepted),
		Note:         renderNote(a, mr.SHA, r.LLM.Model, accepted, r.AcceptLabel),
	}
	if !post {
		return result, nil
	}
	result.NoteURL, err = r.publish(ctx, mr, result.Note)
	if err != nil {
		return Result{}, err
	}
	if len(r.cache) >= maxCached {
		clear(r.cache)
	}
	r.cache[mr.SHA] = result
	return result, nil
}

func (r *Reviewer) publish(ctx context.Context, mr gitlab.MergeRequest, body string) (string, error) {
	if r.selfID == 0 {
		me, err := r.GitLab.CurrentUser(ctx)
		if err != nil {
			return "", err
		}
		r.selfID = me.ID
	}
	notes, err := r.GitLab.Notes(ctx, mr.IID)
	if err != nil {
		return "", err
	}
	for _, n := range notes {
		if n.System || n.Author.ID != r.selfID || !strings.HasPrefix(n.Body, marker) {
			continue
		}
		updated, err := r.GitLab.UpdateNote(ctx, mr.IID, n.ID, body)
		if err != nil {
			return "", err
		}
		return fmt.Sprintf("%s#note_%d", mr.WebURL, updated.ID), nil
	}
	created, err := r.GitLab.CreateNote(ctx, mr.IID, body)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s#note_%d", mr.WebURL, created.ID), nil
}

func parseAssessment(reply string) (Assessment, error) {
	reply = strings.TrimSpace(reply)
	if strings.HasPrefix(reply, "<think>") {
		if i := strings.Index(reply, "</think>"); i >= 0 {
			reply = strings.TrimSpace(reply[i+len("</think>"):])
		}
	}
	reply = strings.TrimPrefix(reply, "```json")
	reply = strings.TrimPrefix(reply, "```")
	reply = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(reply), "```"))

	var a Assessment
	if err := json.Unmarshal([]byte(reply), &a); err != nil {
		return Assessment{}, fmt.Errorf("model reply is not the review JSON: %w", err)
	}
	if _, ok := rank[a.Verdict]; !ok {
		return Assessment{}, fmt.Errorf("model reply has an unknown verdict %q", a.Verdict)
	}
	if len(a.Findings) > maxFindings {
		a.Findings = a.Findings[:maxFindings]
	}
	for i, f := range a.Findings {
		v, ok := severities[f.Severity]
		if !ok {
			a.Findings[i].Severity = "warning"
			v = Check
		}
		if rank[v] > rank[a.Verdict] {
			a.Verdict = v
		}
	}
	return a, nil
}
