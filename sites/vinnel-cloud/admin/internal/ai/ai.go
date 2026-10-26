package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"vinnel-cloud-admin/internal/servers"
)

const (
	AutomationsID = "automations"
	LLMID         = "llm"
	queryTimeout  = 10 * time.Second
	mib           = 1 << 20
	millijoulesKW = 3.6e9
)

type Collector struct {
	URL    string
	Model  string
	Client *http.Client
	TTL    time.Duration

	mu    sync.Mutex
	at    time.Time
	cache []servers.Server
}

func (c *Collector) Infos() []servers.Info {
	if c == nil || c.URL == "" {
		return nil
	}
	return []servers.Info{{ID: AutomationsID, Name: "Automations"}, {ID: LLMID, Name: "LLM"}}
}

func (c *Collector) Servers() []servers.Server {
	if c == nil || c.URL == "" {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cache != nil && time.Since(c.at) < c.TTL {
		return c.cache
	}
	ctx, cancel := context.WithTimeout(context.Background(), queryTimeout)
	defer cancel()
	c.cache = []servers.Server{c.automations(ctx), c.llm(ctx)}
	c.at = time.Now()
	return c.cache
}

type sample struct {
	labels map[string]string
	value  float64
}

type query struct {
	ctx context.Context
	c   *Collector
	err error
}

func (q *query) all(expr string) []sample {
	if q.err != nil {
		return nil
	}
	client := q.c.Client
	if client == nil {
		client = &http.Client{Timeout: queryTimeout}
	}
	req, err := http.NewRequestWithContext(q.ctx, http.MethodGet, strings.TrimRight(q.c.URL, "/")+"/api/v1/query?"+url.Values{"query": {expr}}.Encode(), nil)
	if err != nil {
		q.err = err
		return nil
	}
	resp, err := client.Do(req)
	if err != nil {
		q.err = err
		return nil
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		q.err = err
		return nil
	}
	var out struct {
		Status string `json:"status"`
		Error  string `json:"error"`
		Data   struct {
			Result []struct {
				Metric map[string]string `json:"metric"`
				Value  []any             `json:"value"`
			} `json:"result"`
		} `json:"data"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		q.err = fmt.Errorf("victoriametrics: %d %w", resp.StatusCode, err)
		return nil
	}
	if out.Status != "success" {
		q.err = fmt.Errorf("victoriametrics: %s", out.Error)
		return nil
	}
	samples := make([]sample, 0, len(out.Data.Result))
	for _, r := range out.Data.Result {
		if len(r.Value) != 2 {
			continue
		}
		s, _ := r.Value[1].(string)
		v, err := strconv.ParseFloat(s, 64)
		if err != nil || math.IsNaN(v) || math.IsInf(v, 0) {
			continue
		}
		samples = append(samples, sample{labels: r.Metric, value: v})
	}
	return samples
}

func (q *query) stat(label, unit, expr string) servers.Stat {
	samples := q.all(expr)
	if len(samples) == 0 {
		return servers.Stat{Label: label, Unit: unit, Unknown: true}
	}
	return servers.Stat{Label: label, Unit: unit, Value: samples[0].value}
}

func (q *query) value(expr string) (float64, bool) {
	samples := q.all(expr)
	if len(samples) == 0 {
		return 0, false
	}
	return samples[0].value, true
}

func (q *query) ago(label, expr string) servers.Stat {
	st := q.stat(label, "ago", expr)
	if st.Unknown && q.err == nil {
		st.Unknown, st.Value = false, -1
	}
	return st
}

func finish(s *servers.Server, q *query, up bool, status string) {
	s.Up = up
	s.Status = status
	if !up {
		s.Status = "down"
	}
	if q.err != nil {
		s.Err = "metrics unavailable: " + q.err.Error()
		s.Status = "unknown"
	}
}

func (c *Collector) automations(ctx context.Context) servers.Server {
	q := &query{ctx: ctx, c: c}
	s := servers.Server{ID: AutomationsID, Name: "Automations", Role: "Renovate reviewer · morning digest", Location: "hestia"}
	available, _ := q.value(`max(kube_deployment_status_replicas_available{namespace="automations",deployment="automations"})`)

	s.Stats = []servers.Stat{
		q.stat("Reviews · 7 days", "count", `sum(increase(automations_renovate_verdicts_total[7d]))`),
		q.stat("Held back · 7 days", "count", `sum(increase(automations_renovate_verdicts_total{verdict="breaking"}[7d]))`),
		q.ago("Last review", `time() - max(max_over_time(automations_renovate_last_review_timestamp_seconds[30d]) > 0)`),
		q.stat("Next digest", "in", `max(kube_cronjob_next_schedule_time{namespace="automations",cronjob="digest"}) - time()`),
	}

	week := map[string]float64{}
	for _, smp := range q.all(`sum by (verdict) (increase(automations_renovate_verdicts_total[7d]))`) {
		week[smp.labels["verdict"]] = smp.value
	}
	month := map[string]float64{}
	for _, smp := range q.all(`sum by (verdict) (increase(automations_renovate_verdicts_total[30d]))`) {
		month[smp.labels["verdict"]] = smp.value
	}
	details := map[string]string{"safe": "merged on their own", "check": "merged, worth a look", "breaking": "held for a person"}
	for _, verdict := range []string{"safe", "check", "breaking"} {
		s.Apps = append(s.Apps, servers.App{
			Group:  "Renovate reviews",
			Name:   verdict,
			Detail: details[verdict],
			OK:     true,
			Stats: []servers.Stat{
				{Label: "7 days", Value: math.Round(week[verdict]), Unit: "count"},
				{Label: "30 days", Value: math.Round(month[verdict]), Unit: "count"},
			},
		})
	}
	failedWeek, _ := q.value(`sum(increase(automations_renovate_requests_total{result="failed"}[7d]))`)
	failedMonth, _ := q.value(`sum(increase(automations_renovate_requests_total{result="failed"}[30d]))`)
	s.Apps = append(s.Apps, servers.App{
		Group:  "Renovate reviews",
		Name:   "failed",
		Detail: "the model or GitLab did not answer",
		OK:     failedWeek < 1,
		Stats: []servers.Stat{
			{Label: "7 days", Value: math.Round(failedWeek), Unit: "count"},
			{Label: "30 days", Value: math.Round(failedMonth), Unit: "count"},
		},
	})

	lastSuccess, sent := q.value(`max(kube_cronjob_status_last_successful_time{namespace="automations",cronjob="digest"})`)
	lastSchedule, scheduled := q.value(`max(kube_cronjob_status_last_schedule_time{namespace="automations",cronjob="digest"})`)
	failedRuns, _ := q.value(`count(kube_job_status_failed{namespace="automations",job_name=~"digest-.*"} > 0)`)
	s.Apps = append(s.Apps, servers.App{
		Group:  "Morning digest",
		Name:   "digest",
		Detail: "06:00 Europe/London",
		OK:     !scheduled || (sent && lastSuccess >= lastSchedule),
		Stats: []servers.Stat{
			q.ago("Last sent", `time() - max(kube_cronjob_status_last_successful_time{namespace="automations",cronjob="digest"})`),
			q.stat("Next", "in", `max(kube_cronjob_next_schedule_time{namespace="automations",cronjob="digest"}) - time()`),
			{Label: "Failed runs kept", Value: failedRuns, Unit: "count"},
		},
	})

	finish(&s, q, available >= 1, "running")
	return s
}

func gpuName(model string) string {
	return strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(model, "NVIDIA "), "GeForce "))
}

func (c *Collector) llm(ctx context.Context) servers.Server {
	q := &query{ctx: ctx, c: c}
	s := servers.Server{ID: LLMID, Name: "LLM", Role: c.Model}
	gpu := "GPU"
	if g := q.all(`max by (modelName) (DCGM_FI_DEV_GPU_TEMP)`); len(g) > 0 {
		gpu = gpuName(g[0].labels["modelName"])
		s.Location = gpu
	}
	available, _ := q.value(`max(kube_deployment_status_replicas_available{namespace="llm",deployment="llm"})`)

	vram := q.stat("VRAM", "bytes", `max(DCGM_FI_DEV_FB_USED) * `+strconv.Itoa(mib))
	if total, ok := q.value(`max(DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * ` + strconv.Itoa(mib)); ok {
		vram.Max = total
	}
	util := q.stat("GPU", "percent", `max(DCGM_FI_DEV_GPU_UTIL)`)
	util.Max = 100
	power := q.stat("Power", "watts", `max(DCGM_FI_DEV_POWER_USAGE)`)
	if limit, ok := q.value(`max(DCGM_FI_DEV_POWER_MGMT_LIMIT)`); ok {
		power.Max = limit
	}
	s.Stats = []servers.Stat{vram, util, q.stat("Temperature", "celsius", `max(DCGM_FI_DEV_GPU_TEMP)`), power}

	busy, _ := q.value(`max(llamacpp:requests_processing)`)
	state := "idle"
	if busy >= 1 {
		state = "answering"
	}
	s.Apps = append(s.Apps, servers.App{
		Group:  "Model",
		Name:   c.Model,
		Detail: state,
		OK:     available >= 1,
		Stats: []servers.Stat{
			q.stat("Read · 24 h", "tokens", `sum(increase(llamacpp:prompt_tokens_total[24h]))`),
			q.stat("Written · 24 h", "tokens", `sum(increase(llamacpp:tokens_predicted_total[24h]))`),
			q.stat("Reading", "tokens/s", `max(llamacpp:prompt_tokens_seconds)`),
			q.stat("Writing", "tokens/s", `max(llamacpp:predicted_tokens_seconds)`),
			q.stat("Longest context", "tokens", `max(llamacpp:n_tokens_max)`),
		},
	})

	xid, _ := q.value(`max(DCGM_FI_DEV_XID_ERRORS)`)
	detail := "no driver errors"
	if xid > 0 {
		detail = fmt.Sprintf("last XID error %.0f", xid)
	}
	s.Apps = append(s.Apps, servers.App{
		Group:  "GPU",
		Name:   gpu,
		Detail: detail,
		OK:     xid == 0,
		Stats: []servers.Stat{
			q.stat("SM clock", "mhz", `max(DCGM_FI_DEV_SM_CLOCK)`),
			q.stat("Memory clock", "mhz", `max(DCGM_FI_DEV_MEM_CLOCK)`),
			q.stat("Power · 24 h avg", "watts", `max(avg_over_time(DCGM_FI_DEV_POWER_USAGE[24h]))`),
			q.stat("Peak · 24 h", "celsius", `max(max_over_time(DCGM_FI_DEV_GPU_TEMP[24h]))`),
			q.stat("Energy · 24 h", "kwh", `max(increase(DCGM_FI_DEV_TOTAL_ENERGY_CONSUMPTION[24h])) / `+strconv.FormatFloat(millijoulesKW, 'g', -1, 64)),
		},
	})

	finish(&s, q, available >= 1, state)
	return s
}
