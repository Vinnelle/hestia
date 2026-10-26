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
	_ "time/tzdata"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"automations/internal/digest"
	"automations/internal/gitlab"
	"automations/internal/kube"
	"automations/internal/llm"
	"automations/internal/metrics"
	"automations/internal/prom"
	"automations/internal/renovate"
	"automations/internal/telemetry"
)

var (
	reviewRequests = metrics.NewCounter("automations_renovate_requests_total", "Review requests from the renovate_review job, by result", "result")
	reviewVerdicts = metrics.NewCounter("automations_renovate_verdicts_total", "Fresh Renovate reviews, by verdict", "verdict")
	reviewSeconds  = metrics.NewCounter("automations_renovate_review_seconds_total", "Seconds spent on fresh Renovate reviews", "")
	lastReview     = metrics.NewGauge("automations_renovate_last_review_timestamp_seconds", "Unix time the last fresh Renovate review finished", "")
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
		started := time.Now()
		result, err := reviewer.Review(r.Context(), in.MergeRequestIID, true)
		if err != nil {
			status := http.StatusBadGateway
			outcome := "failed"
			if errors.Is(err, renovate.ErrNotRenovate) {
				status = http.StatusUnprocessableEntity
				outcome = "refused"
			}
			reviewRequests.Add(outcome, 1)
			log.Printf("renovate review: mr=!%d err=%v", in.MergeRequestIID, err)
			writeJSON(w, status, map[string]string{"err": err.Error()})
			return
		}
		if result.Cached {
			reviewRequests.Add("cached", 1)
		} else {
			reviewRequests.Add("reviewed", 1)
			reviewVerdicts.Add(string(result.Verdict), 1)
			reviewSeconds.Add("", time.Since(started).Seconds())
			lastReview.Set("", float64(time.Now().Unix()))
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

	metricsAddr := env("METRICS_ADDR", ":9090")
	go func() {
		ms := &http.Server{
			Addr:              metricsAddr,
			Handler:           metrics.Handler(reviewRequests, reviewVerdicts, reviewSeconds, lastReview),
			ReadHeaderTimeout: 5 * time.Second,
		}
		log.Fatal(ms.ListenAndServe())
	}()

	addr := env("LISTEN_ADDR", ":8080")
	srv := &http.Server{
		Addr:              addr,
		Handler:           otelhttp.NewHandler(mux, "http"),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("automations listening on %s, metrics on %s", addr, metricsAddr)
	log.Fatal(srv.ListenAndServe())
}

func location() *time.Location {
	loc, err := time.LoadLocation(env("DIGEST_TIMEZONE", "Europe/London"))
	if err != nil {
		log.Fatalf("DIGEST_TIMEZONE: %v", err)
	}
	return loc
}

func runDigest(args []string) {
	flags := flag.NewFlagSet("digest", flag.ExitOnError)
	preview := flags.String("preview", "", "render the email from a facts JSON file instead of collecting and sending")
	summaryFile := flags.String("summary", "", "with -preview, the summary JSON to render; without it the LLM at LLM_BASE_URL writes one")
	out := flags.String("out", "digest.html", "with -preview, where to write the HTML")
	collect := flags.String("collect", "", "collect the last 24 hours of facts into this JSON file, from VICTORIA_METRICS_URL and GitLab when GITLAB_TOKEN is set, then exit")
	flags.Parse(args)

	if *preview != "" {
		previewDigest(*preview, *summaryFile, *out)
		return
	}
	if *collect != "" {
		collectFacts(*collect)
		return
	}

	require("GITLAB_PROJECT_ID", "GITLAB_TOKEN", "LLM_BASE_URL", "LLM_MODEL", "RESEND_API_KEY", "DIGEST_TO", "POD_NAMESPACE")
	client, err := kube.InCluster()
	if err != nil {
		log.Fatalf("digest: %v", err)
	}
	reviewer := newReviewer()
	d := &digest.Digest{
		Collector: &digest.Collector{
			Prom:           &prom.Client{BaseURL: env("VICTORIA_METRICS_URL", "http://vmsingle-vm.observability.svc.cluster.local:8428")},
			Kube:           client,
			GitLab:         reviewer.GitLab,
			DefaultBranch:  env("GITLAB_DEFAULT_BRANCH", "prd"),
			RenovatePrefix: reviewer.BranchPrefix,
		},
		LLM:      reviewer.LLM,
		State:    &digest.State{Kube: client, Namespace: os.Getenv("POD_NAMESPACE"), Name: env("DIGEST_STATE", "digest-state")},
		Mailer:   &digest.Resend{APIKey: os.Getenv("RESEND_API_KEY")},
		From:     env("DIGEST_FROM", "hestia <digest@vinnel.cloud>"),
		To:       strings.Split(os.Getenv("DIGEST_TO"), ","),
		Location: location(),
		AdminURL: env("ADMIN_URL", "https://admin.vinnel.cloud"),
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Minute)
	defer cancel()
	if err := d.Run(ctx); err != nil {
		log.Fatalf("digest: %v", err)
	}
}

func collectFacts(out string) {
	require("VICTORIA_METRICS_URL")
	c := &digest.Collector{
		Prom:           &prom.Client{BaseURL: os.Getenv("VICTORIA_METRICS_URL")},
		DefaultBranch:  env("GITLAB_DEFAULT_BRANCH", "prd"),
		RenovatePrefix: env("RENOVATE_BRANCH_PREFIX", "renovate/"),
	}
	if os.Getenv("GITLAB_TOKEN") != "" {
		c.GitLab = newReviewer().GitLab
	}
	to := time.Now().UTC().Truncate(time.Minute)
	facts, _ := c.Collect(context.Background(), to.Add(-24*time.Hour), to, digest.Snapshot{})
	data, err := json.MarshalIndent(facts, "", "  ")
	if err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile(out, data, 0o644); err != nil {
		log.Fatal(err)
	}
	log.Printf("wrote %s (%d gaps)", out, len(facts.Gaps))
}

func previewDigest(factsFile, summaryFile, out string) {
	var facts digest.Facts
	readJSON(factsFile, &facts)
	checks := digest.Checks(facts)
	var summary digest.Summary
	if summaryFile != "" {
		readJSON(summaryFile, &summary)
		summary.Model = env("LLM_MODEL", summary.Model)
	} else {
		require("LLM_BASE_URL", "LLM_MODEL")
		s, err := digest.Summarize(context.Background(), newReviewer().LLM, facts, checks)
		if err != nil {
			log.Printf("digest summary: %v", err)
			s = digest.Fallback(checks, err)
		}
		summary = s
	}
	view := digest.Build(facts, summary, checks, location(), env("ADMIN_URL", "https://admin.vinnel.cloud"))
	html, err := digest.Render(view)
	if err != nil {
		log.Fatalf("digest render: %v", err)
	}
	if err := os.WriteFile(out, []byte(html), 0o644); err != nil {
		log.Fatalf("digest: %v", err)
	}
	fmt.Println(digest.Subject(summary, facts.To.In(location())))
	fmt.Print(digest.Text(view))
	log.Printf("wrote %s (%d bytes)", out, len(html))
}

func readJSON(path string, v any) {
	data, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	if err := json.Unmarshal(data, v); err != nil {
		log.Fatalf("%s: %v", path, err)
	}
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
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "review":
			review(os.Args[2:])
			return
		case "digest":
			runDigest(os.Args[2:])
			return
		}
	}
	serve()
}
