package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"automations/internal/gitlab"
	"automations/internal/llm"
	"automations/internal/renovate"
	"automations/internal/telemetry"
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int64) int64 {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		log.Fatalf("%s: %v", key, err)
	}
	return n
}

func require(keys ...string) {
	var missing []string
	for _, key := range keys {
		if os.Getenv(key) == "" {
			missing = append(missing, key)
		}
	}
	if len(missing) > 0 {
		log.Fatalf("missing %s", strings.Join(missing, ", "))
	}
}

func newReviewer() *renovate.Reviewer {
	transport := otelhttp.NewTransport(http.DefaultTransport)
	return &renovate.Reviewer{
		GitLab: &gitlab.Client{
			BaseURL:   env("GITLAB_API_URL", "https://gitlab.vinnel.cloud/api/v4"),
			ProjectID: os.Getenv("GITLAB_PROJECT_ID"),
			Token:     os.Getenv("GITLAB_TOKEN"),
			HTTP:      &http.Client{Timeout: 30 * time.Second, Transport: transport},
		},
		LLM: &llm.Client{
			BaseURL: os.Getenv("LLM_BASE_URL"),
			Model:   os.Getenv("LLM_MODEL"),
			APIKey:  os.Getenv("LLM_API_KEY"),
			HTTP:    &http.Client{Timeout: 15 * time.Minute, Transport: transport},
		},
		AuthorID:     envInt("RENOVATE_AUTHOR_ID", 0),
		BranchPrefix: env("RENOVATE_BRANCH_PREFIX", "renovate/"),
		AcceptLabel:  env("REVIEW_ACCEPT_LABEL", "review-accepted"),
		MaxPrompt:    int(envInt("REVIEW_MAX_PROMPT_BYTES", 48000)),
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("writeJSON: %v", err)
	}
}

func reviewHandler(reviewer *renovate.Reviewer) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var in struct {
			MergeRequestIID int64 `json:"merge_request_iid"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1024)).Decode(&in); err != nil || in.MergeRequestIID <= 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"err": "malformed request"})
			return
		}
		result, err := reviewer.Review(r.Context(), in.MergeRequestIID, true)
		if err != nil {
			status := http.StatusBadGateway
			if errors.Is(err, renovate.ErrNotRenovate) {
				status = http.StatusUnprocessableEntity
			}
			log.Printf("renovate review: mr=!%d err=%v", in.MergeRequestIID, err)
			writeJSON(w, status, map[string]string{"err": err.Error()})
			return
		}
		log.Printf("renovate review: mr=!%d sha=%s verdict=%s accepted=%v pass=%v", result.MergeRequest, result.SHA, result.Verdict, result.Accepted, result.Pass)
		writeJSON(w, http.StatusOK, result)
	}
}

func serve() {
	require("GITLAB_PROJECT_ID", "GITLAB_TOKEN", "LLM_BASE_URL", "LLM_MODEL", "RENOVATE_AUTHOR_ID")

	shutdownTracing, err := telemetry.Setup(context.Background(), env("OTEL_COLLECTOR_ENDPOINT", ""))
	if err != nil {
		log.Fatalf("otel setup: %v", err)
	}
	defer shutdownTracing(context.Background())

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("POST /renovate/reviews", reviewHandler(newReviewer()))

	addr := env("LISTEN_ADDR", ":8080")
	srv := &http.Server{
		Addr:              addr,
		Handler:           otelhttp.NewHandler(mux, "http"),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("automations listening on %s", addr)
	log.Fatal(srv.ListenAndServe())
}

func review(args []string) {
	flags := flag.NewFlagSet("review", flag.ExitOnError)
	iid := flags.Int64("mr", 0, "IID of the Renovate merge request to review")
	post := flags.Bool("post", false, "post the note to the merge request instead of printing it")
	flags.Parse(args)
	if *iid <= 0 {
		log.Fatal("review: -mr is required")
	}
	require("GITLAB_PROJECT_ID", "GITLAB_TOKEN", "LLM_BASE_URL", "LLM_MODEL")

	result, err := newReviewer().Review(context.Background(), *iid, *post)
	if err != nil {
		log.Fatalf("review: %v", err)
	}
	if *post {
		fmt.Println(result.NoteURL)
	} else {
		fmt.Print(result.Note)
	}
	log.Printf("verdict=%s accepted=%v pass=%v", result.Verdict, result.Accepted, result.Pass)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "review" {
		review(os.Args[2:])
		return
	}
	serve()
}
