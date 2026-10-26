package ai

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"vinnel-cloud-admin/internal/servers"
)

var answers = []struct{ match, result string }{
	{`kube_deployment_status_replicas_available{namespace="automations"`, `[{"metric":{},"value":[0,"1"]}]`},
	{`kube_deployment_status_replicas_available{namespace="llm"`, `[{"metric":{},"value":[0,"1"]}]`},
	{`sum by (verdict) (increase(automations_renovate_verdicts_total[7d]))`, `[{"metric":{"verdict":"safe"},"value":[0,"11.4"]},{"metric":{"verdict":"breaking"},"value":[0,"1"]}]`},
	{`automations_renovate_verdicts_total{verdict="breaking"}[7d]`, `[{"metric":{},"value":[0,"1"]}]`},
	{`sum(increase(automations_renovate_verdicts_total[7d]))`, `[{"metric":{},"value":[0,"12"]}]`},
	{`automations_renovate_last_review_timestamp_seconds`, `[]`},
	{`kube_cronjob_status_last_successful_time`, `[{"metric":{},"value":[0,"1700000000"]}]`},
	{`kube_cronjob_status_last_schedule_time`, `[{"metric":{},"value":[0,"1700000000"]}]`},
	{`kube_cronjob_next_schedule_time`, `[{"metric":{},"value":[0,"3600"]}]`},
	{`max by (modelName)`, `[{"metric":{"modelName":"NVIDIA GeForce RTX 4070 Ti"},"value":[0,"41"]}]`},
	{`DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE`, `[{"metric":{},"value":[0,"12884901888"]}]`},
	{`max(DCGM_FI_DEV_FB_USED)`, `[{"metric":{},"value":[0,"8396996608"]}]`},
	{`max(DCGM_FI_DEV_GPU_UTIL)`, `[{"metric":{},"value":[0,"37"]}]`},
	{`max(DCGM_FI_DEV_XID_ERRORS)`, `[{"metric":{},"value":[0,"0"]}]`},
	{`llamacpp:requests_processing`, `[{"metric":{},"value":[0,"1"]}]`},
	{`llamacpp:predicted_tokens_seconds`, `[{"metric":{},"value":[0,"57.2"]}]`},
}

func fakeVM(t *testing.T) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("query")
		result := `[]`
		for _, a := range answers {
			if strings.Contains(q, a.match) {
				result = a.result
				break
			}
		}
		w.Write([]byte(`{"status":"success","data":{"resultType":"vector","result":` + result + `}}`))
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

func stat(t *testing.T, stats []servers.Stat, label string) servers.Stat {
	t.Helper()
	for _, s := range stats {
		if s.Label == label {
			return s
		}
	}
	t.Fatalf("no %q in %+v", label, stats)
	return servers.Stat{}
}

func TestServersReadVictoriaMetrics(t *testing.T) {
	c := &Collector{URL: fakeVM(t), Model: "gemma-4-12b-it"}
	got := c.Servers()
	if len(got) != 2 {
		t.Fatalf("servers = %+v", got)
	}

	auto := got[0]
	if !auto.Up || auto.Status != "running" || auto.Err != "" {
		t.Fatalf("automations = %+v", auto)
	}
	if s := stat(t, auto.Stats, "Reviews · 7 days"); s.Value != 12 || s.Unknown {
		t.Fatalf("reviews = %+v", s)
	}
	if s := stat(t, auto.Stats, "Last review"); s.Value != -1 || s.Unknown {
		t.Fatalf("last review with no reviews = %+v, want never", s)
	}
	if s := stat(t, auto.Stats, "Next digest"); s.Value != 3600 || s.Unit != "in" {
		t.Fatalf("next digest = %+v", s)
	}
	var safe, digest servers.App
	for _, a := range auto.Apps {
		switch a.Name {
		case "safe":
			safe = a
		case "digest":
			digest = a
		}
	}
	if stat(t, safe.Stats, "7 days").Value != 11 || !digest.OK {
		t.Fatalf("safe = %+v digest = %+v", safe, digest)
	}

	llm := got[1]
	if !llm.Up || llm.Status != "answering" || llm.Role != "gemma-4-12b-it" || llm.Location != "RTX 4070 Ti" {
		t.Fatalf("llm = %+v", llm)
	}
	if vram := stat(t, llm.Stats, "VRAM"); vram.Max != 12884901888 || vram.Value != 8396996608 {
		t.Fatalf("vram = %+v", vram)
	}
	if util := stat(t, llm.Stats, "GPU"); util.Value != 37 || util.Max != 100 || util.Unit != "percent" {
		t.Fatalf("gpu = %+v", util)
	}
	if temp := stat(t, llm.Stats, "Temperature"); !temp.Unknown {
		t.Fatalf("temperature without data = %+v, want unknown", temp)
	}
}

func TestServersReportAnUnreachableSource(t *testing.T) {
	c := &Collector{URL: "http://127.0.0.1:1", Model: "m"}
	for _, s := range c.Servers() {
		if s.Status != "unknown" || !strings.HasPrefix(s.Err, "metrics unavailable") {
			t.Fatalf("server = %+v", s)
		}
	}
	if (&Collector{}).Infos() != nil || (&Collector{}).Servers() != nil {
		t.Fatal("a collector without a URL shows pages")
	}
}
