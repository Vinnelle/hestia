package digest

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"

	"automations/internal/gitlab"
	"automations/internal/kube"
	"automations/internal/prom"
)

const (
	publicHosts  = `host!~".*\\.internal|_"`
	noisyAlerts  = `alertname!~"Watchdog|InfoInhibitor"`
	maxRows      = 8
	certWarnDays = 21
)

type Collector struct {
	Prom           *prom.Client
	Kube           *kube.Client
	GitLab         *gitlab.Client
	DefaultBranch  string
	RenovatePrefix string
}

type run struct {
	ctx  context.Context
	c    *Collector
	from time.Time
	to   time.Time
	gaps []string
	seen map[string]bool
}

func (r *run) gap(section string, err error) {
	if r.seen[section] {
		return
	}
	r.seen[section] = true
	msg := err.Error()
	if len(msg) > 160 {
		msg = msg[:160] + "..."
	}
	r.gaps = append(r.gaps, section+": "+msg)
}

func (r *run) expand(q string) string {
	window := fmt.Sprintf("%ds", max(int(r.to.Sub(r.from).Seconds()), 60))
	return strings.NewReplacer("$W", window, "$FROM", strconv.FormatInt(r.from.Unix(), 10)).Replace(q)
}

func (r *run) vec(section, q string) []prom.Sample {
	if r.c.Prom == nil {
		r.gap(section, fmt.Errorf("no metrics source configured"))
		return nil
	}
	samples, err := r.c.Prom.Query(r.ctx, r.expand(q), r.to)
	if err != nil {
		r.gap(section, err)
		return nil
	}
	return samples
}

func (r *run) one(section, q string) float64 {
	samples := r.vec(section, q)
	if len(samples) == 0 || math.IsNaN(samples[0].Value) {
		return 0
	}
	return samples[0].Value
}

func byValue(samples []prom.Sample) []prom.Sample {
	sort.SliceStable(samples, func(i, j int) bool { return samples[i].Value > samples[j].Value })
	return samples
}

func head[T any](rows []T) []T {
	if len(rows) > maxRows {
		return rows[:maxRows]
	}
	return rows
}

func (c *Collector) Collect(ctx context.Context, from, to time.Time, prev Snapshot) (Facts, map[string][]string) {
	r := &run{ctx: ctx, c: c, from: from, to: to, seen: map[string]bool{}}
	f := Facts{From: from, To: to, First: prev.SentAt.IsZero()}
	f.Cluster = r.cluster()
	f.Traffic = r.traffic()
	f.Alerts = r.alerts()
	f.Security = r.security(prev)
	f.Certificates = r.certificates()
	f.AI = r.ai()
	workloads := r.workloads()
	f.Changes = r.changes(prev, workloads, f.Cluster)
	f.Gaps = r.gaps
	return f, workloads
}

func (r *run) cluster() Cluster {
	const s = "cluster"
	busy := `sum(rate(node_cpu_seconds_total{job="node-exporter",mode!~"idle|iowait|steal"}[5m]))`
	used := `sum(node_memory_MemTotal_bytes{job="node-exporter"} - node_memory_MemAvailable_bytes{job="node-exporter"})`
	c := Cluster{
		Ready: r.one(s, `max(kube_node_status_condition{condition="Ready",status="true"})`) == 1,
		CPU: Usage{
			Used:  r.one(s, busy),
			Peak:  r.one(s, "max_over_time(("+busy+")[$W:5m])"),
			Total: r.one(s, `count(node_cpu_seconds_total{job="node-exporter",mode="idle"})`),
		},
		Memory: Usage{
			Used:  r.one(s, used),
			Peak:  r.one(s, "max_over_time(("+used+")[$W:5m])"),
			Total: r.one(s, `sum(node_memory_MemTotal_bytes{job="node-exporter"})`),
		},
		PodsRunning: int(r.one(s, `sum(kube_pod_status_phase{phase="Running"})`)),
		PodsTotal:   int(r.one(s, `sum(kube_pod_status_phase{phase=~"Running|Pending|Unknown|Failed"})`)),
	}
	if info := r.vec(s, `kube_node_info`); len(info) > 0 {
		c.Talos = strings.TrimSuffix(strings.TrimPrefix(info[0].Labels["os_image"], "Talos ("), ")")
		c.Kubernetes = info[0].Labels["kubelet_version"]
		c.Kernel = info[0].Labels["kernel_version"]
	}

	avail := map[string]float64{}
	for _, smp := range r.vec(s, `node_filesystem_avail_bytes{job="node-exporter",fstype="xfs"}`) {
		avail[smp.Labels["mountpoint"]] = smp.Value
	}
	for _, smp := range r.vec(s, `node_filesystem_size_bytes{job="node-exporter",fstype="xfs"}`) {
		mount := smp.Labels["mountpoint"]
		c.Filesystems = append(c.Filesystems, Filesystem{Mount: mount, Used: smp.Value - avail[mount], Size: smp.Value})
	}
	sort.Slice(c.Filesystems, func(i, j int) bool { return c.Filesystems[i].Mount < c.Filesystems[j].Mount })

	for _, smp := range r.vec(s, `max by (namespace, pod, reason) (kube_pod_container_status_waiting_reason{reason!~"ContainerCreating|PodInitializing"} == 1)`) {
		c.PodIssues = append(c.PodIssues, PodIssue{Namespace: smp.Labels["namespace"], Pod: smp.Labels["pod"], Reason: smp.Labels["reason"]})
	}
	for _, smp := range r.vec(s, `max by (namespace, pod, phase) (kube_pod_status_phase{phase=~"Pending|Unknown|Failed"} == 1)`) {
		c.PodIssues = append(c.PodIssues, PodIssue{Namespace: smp.Labels["namespace"], Pod: smp.Labels["pod"], Reason: smp.Labels["phase"]})
	}
	c.PodIssues = head(c.PodIssues)

	for _, smp := range byValue(r.vec(s, `sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total[$W])) >= 1`)) {
		c.Restarts = append(c.Restarts, Restart{Namespace: smp.Labels["namespace"], Pod: smp.Labels["pod"], Count: int(math.Round(smp.Value))})
	}
	c.Restarts = head(c.Restarts)

	cpuByNamespace := map[string]float64{}
	for _, smp := range r.vec(s, `sum by (namespace) (rate(container_cpu_usage_seconds_total{container!="",container!="POD"}[5m]))`) {
		cpuByNamespace[smp.Labels["namespace"]] = smp.Value
	}
	for _, smp := range byValue(r.vec(s, `topk(5, sum by (namespace) (container_memory_working_set_bytes{container!="",container!="POD"}))`)) {
		ns := smp.Labels["namespace"]
		c.TopMemory = append(c.TopMemory, NamespaceUsage{Namespace: ns, Memory: smp.Value, CPU: cpuByNamespace[ns]})
	}

	capacity := map[string]float64{}
	for _, smp := range r.vec(s, `max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_capacity_bytes)`) {
		capacity[smp.Labels["namespace"]+"/"+smp.Labels["persistentvolumeclaim"]] = smp.Value
	}
	for _, smp := range r.vec(s, `max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes)`) {
		key := smp.Labels["namespace"] + "/" + smp.Labels["persistentvolumeclaim"]
		if total := capacity[key]; total > 0 && smp.Value/total > 0.75 {
			c.FullVolumes = append(c.FullVolumes, Volume{Namespace: smp.Labels["namespace"], Claim: smp.Labels["persistentvolumeclaim"], Used: smp.Value, Capacity: total})
		}
	}

	for _, smp := range r.vec(s, `max by (namespace, job_name) (kube_job_status_failed > 0) and on (namespace, job_name) (kube_job_created > $FROM)`) {
		c.FailedJobs = append(c.FailedJobs, smp.Labels["namespace"]+"/"+smp.Labels["job_name"])
	}
	sort.Strings(c.FailedJobs)
	c.FailedJobs = head(c.FailedJobs)
	return c
}

func (r *run) traffic() Traffic {
	const s = "traffic"
	t := Traffic{
		Requests:         r.one(s, `sum(increase(nginx_ingress_controller_requests{`+publicHosts+`}[$W]))`),
		PreviousRequests: r.one(s, `sum(increase(nginx_ingress_controller_requests{`+publicHosts+`}[$W] offset $W))`),
		ServerErrors:     r.one(s, `sum(increase(nginx_ingress_controller_requests{`+publicHosts+`,status=~"5.."}[$W]))`),
		ClientErrors:     r.one(s, `sum(increase(nginx_ingress_controller_requests{`+publicHosts+`,status=~"4.."}[$W]))`),
		BytesOut:         r.one(s, `sum(increase(nginx_ingress_controller_response_size_sum{`+publicHosts+`}[$W]))`),
		TunnelIn:         r.one(s, `sum(increase(node_network_receive_bytes_total{job="node-exporter",device="wg0"}[$W]))`),
		TunnelOut:        r.one(s, `sum(increase(node_network_transmit_bytes_total{job="node-exporter",device="wg0"}[$W]))`),
	}
	errors := map[string]float64{}
	for _, smp := range r.vec(s, `sum by (host) (increase(nginx_ingress_controller_requests{`+publicHosts+`,status=~"5.."}[$W]))`) {
		errors[smp.Labels["host"]] = smp.Value
	}
	bytes := map[string]float64{}
	for _, smp := range r.vec(s, `sum by (host) (increase(nginx_ingress_controller_response_size_sum{`+publicHosts+`}[$W]))`) {
		bytes[smp.Labels["host"]] = smp.Value
	}
	for _, smp := range byValue(r.vec(s, `sum by (host) (increase(nginx_ingress_controller_requests{`+publicHosts+`}[$W])) >= 1`)) {
		host := smp.Labels["host"]
		t.Hosts = append(t.Hosts, Host{Host: host, Requests: smp.Value, Errors: errors[host], Bytes: bytes[host]})
	}
	t.Hosts = head(t.Hosts)
	return t
}

func (r *run) alerts() []Alert {
	const s = "alerts"
	firing := map[string]bool{}
	for _, smp := range r.vec(s, `ALERTS{alertstate="firing",`+noisyAlerts+`}`) {
		firing[smp.Labels["alertname"]+"/"+smp.Labels["namespace"]] = true
	}
	var alerts []Alert
	for _, smp := range r.vec(s, `max by (alertname, severity, namespace) (max_over_time(ALERTS{alertstate="firing",`+noisyAlerts+`}[$W]))`) {
		name, ns := smp.Labels["alertname"], smp.Labels["namespace"]
		alerts = append(alerts, Alert{Name: name, Severity: smp.Labels["severity"], Namespace: ns, Firing: firing[name+"/"+ns]})
	}
	sort.Slice(alerts, func(i, j int) bool {
		if alerts[i].Firing != alerts[j].Firing {
			return alerts[i].Firing
		}
		return alerts[i].Name < alerts[j].Name
	})
	return head(alerts)
}

func (r *run) security(prev Snapshot) Security {
	const s = "security"
	sec := Security{PrevCritical: prev.Critical, PrevHigh: prev.High, Known: !prev.SentAt.IsZero()}
	for _, smp := range r.vec(s, `sum by (severity) (max by (image_registry, image_repository, image_tag, severity) (trivy_image_vulnerabilities{severity=~"Critical|High"}))`) {
		switch smp.Labels["severity"] {
		case "Critical":
			sec.Critical = int(smp.Value)
		case "High":
			sec.High = int(smp.Value)
		}
	}
	for _, smp := range byValue(r.vec(s, `topk(3, max by (image_repository, image_tag) (trivy_image_vulnerabilities{severity="Critical"}) > 0)`)) {
		image := smp.Labels["image_repository"]
		if tag := smp.Labels["image_tag"]; tag != "" {
			image += ":" + tag
		}
		sec.Worst = append(sec.Worst, ImageVulns{Image: image, Critical: int(smp.Value)})
	}
	return sec
}

func (r *run) certificates() []Certificate {
	const s = "certificates"
	notReady := map[string]bool{}
	for _, smp := range r.vec(s, `max by (exported_namespace, name) (certmanager_certificate_ready_status{condition="False"} == 1)`) {
		notReady[smp.Labels["exported_namespace"]+"/"+smp.Labels["name"]] = true
	}
	var certs []Certificate
	for _, smp := range r.vec(s, `min by (exported_namespace, name) (certmanager_certificate_expiration_timestamp_seconds) - time()`) {
		ns, name := smp.Labels["exported_namespace"], smp.Labels["name"]
		certs = append(certs, Certificate{Name: name, Namespace: ns, Days: smp.Value / 86400, Ready: !notReady[ns+"/"+name]})
	}
	sort.Slice(certs, func(i, j int) bool { return certs[i].Days < certs[j].Days })
	var keep []Certificate
	for i, cert := range certs {
		if i < 3 || cert.Days < certWarnDays || !cert.Ready {
			keep = append(keep, cert)
		}
	}
	return keep
}

func (r *run) ai() AI {
	const s = "ai"
	a := AI{
		PromptTokens:    r.one(s, `sum(increase(llamacpp:prompt_tokens_total[$W]))`),
		GeneratedTokens: r.one(s, `sum(increase(llamacpp:tokens_predicted_total[$W]))`),
		Speed:           r.one(s, `max(llamacpp:predicted_tokens_seconds)`),
		GPUTempMax:      r.one(s, `max(max_over_time(DCGM_FI_DEV_GPU_TEMP[$W]))`),
		GPUPowerAvg:     r.one(s, `avg(avg_over_time(DCGM_FI_DEV_POWER_USAGE[$W]))`),
		VRAMUsed:        r.one(s, `max(DCGM_FI_DEV_FB_USED)`) * (1 << 20),
		VRAMTotal:       r.one(s, `max(DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)`) * (1 << 20),
	}
	if gpus := r.vec(s, `max by (modelName) (DCGM_FI_DEV_GPU_TEMP)`); len(gpus) > 0 {
		a.GPU = strings.TrimPrefix(gpus[0].Labels["modelName"], "NVIDIA ")
	}
	return a
}

type workloadList struct {
	Items []struct {
		Metadata struct {
			Namespace string `json:"namespace"`
			Name      string `json:"name"`
		} `json:"metadata"`
		Spec struct {
			Template struct {
				Spec struct {
					Containers []struct {
						Image string `json:"image"`
					} `json:"containers"`
				} `json:"spec"`
			} `json:"template"`
		} `json:"spec"`
	} `json:"items"`
}

func (r *run) workloads() map[string][]string {
	if r.c.Kube == nil {
		return nil
	}
	out := map[string][]string{}
	for _, kind := range []string{"deployments", "statefulsets", "daemonsets"} {
		var list workloadList
		if err := r.c.Kube.Get(r.ctx, "/apis/apps/v1/"+kind, &list); err != nil {
			r.gap("workloads", err)
			return nil
		}
		for _, item := range list.Items {
			var images []string
			for _, c := range item.Spec.Template.Spec.Containers {
				images = append(images, c.Image)
			}
			out[item.Metadata.Namespace+"/"+strings.TrimSuffix(kind, "s")+"/"+item.Metadata.Name] = images
		}
	}
	return out
}

func shortImage(image string) string {
	if at := strings.Index(image, "@sha256:"); at >= 0 {
		digest := image[at+len("@sha256:"):]
		if len(digest) > 12 {
			digest = digest[:12]
		}
		image = image[:at] + "@" + digest
	}
	if slash := strings.LastIndex(image, "/"); slash >= 0 {
		image = image[slash+1:]
	}
	return image
}

func (r *run) changes(prev Snapshot, workloads map[string][]string, cluster Cluster) Changes {
	ch := Changes{Reviews: map[string]int{}}
	for _, smp := range r.vec("reviews", `sum by (verdict) (increase(automations_renovate_verdicts_total[$W]))`) {
		if n := int(math.Round(smp.Value)); n > 0 {
			ch.Reviews[smp.Labels["verdict"]] = n
		}
	}

	if prev.Talos != "" && cluster.Talos != "" && prev.Talos != cluster.Talos {
		ch.Upgrades = append(ch.Upgrades, "Talos "+prev.Talos+" → "+cluster.Talos)
	}
	if prev.Kubernetes != "" && cluster.Kubernetes != "" && prev.Kubernetes != cluster.Kubernetes {
		ch.Upgrades = append(ch.Upgrades, "Kubernetes "+prev.Kubernetes+" → "+cluster.Kubernetes)
	}

	if workloads != nil && prev.Images != nil {
		var keys []string
		for k := range workloads {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			before, ok := prev.Images[k]
			if !ok {
				ch.Added = append(ch.Added, k)
				continue
			}
			now := workloads[k]
			for i := range now {
				if i < len(before) && before[i] != now[i] {
					ch.Images = append(ch.Images, ImageChange{Workload: k, From: shortImage(before[i]), To: shortImage(now[i])})
				}
			}
		}
		for k := range prev.Images {
			if _, ok := workloads[k]; !ok {
				ch.Removed = append(ch.Removed, k)
			}
		}
		sort.Strings(ch.Removed)
		ch.Images = head(ch.Images)
	}

	if r.c.GitLab == nil {
		return ch
	}
	commits, err := r.c.GitLab.Commits(r.ctx, r.c.DefaultBranch, r.from)
	if err != nil {
		r.gap("gitlab", err)
	}
	for _, c := range commits {
		if strings.HasPrefix(c.Title, "deploy: pin ") {
			ch.ImagePins++
			continue
		}
		ch.Commits = append(ch.Commits, Commit{SHA: c.ShortID, Title: c.Title, Author: c.AuthorName, URL: c.WebURL})
	}
	ch.Commits = head(ch.Commits)

	merged, err := r.c.GitLab.MergeRequests(r.ctx, "merged", r.from)
	if err != nil {
		r.gap("gitlab", err)
	}
	for _, mr := range merged {
		if mr.MergedAt == nil || mr.MergedAt.Before(r.from) {
			continue
		}
		ch.Merged = append(ch.Merged, Merge{IID: mr.IID, Title: mr.Title, Renovate: strings.HasPrefix(mr.SourceBranch, r.c.RenovatePrefix), URL: mr.WebURL})
	}

	open, err := r.c.GitLab.MergeRequests(r.ctx, "opened", time.Time{})
	if err != nil {
		r.gap("gitlab", err)
	}
	for _, mr := range open {
		if strings.HasPrefix(mr.SourceBranch, r.c.RenovatePrefix) {
			ch.OpenRenovate++
		}
	}

	failed, err := r.c.GitLab.Pipelines(r.ctx, "failed", r.from)
	if err != nil {
		r.gap("gitlab", err)
	}
	for _, p := range failed {
		ch.FailedPipelines = append(ch.FailedPipelines, Pipeline{ID: p.ID, Ref: p.Ref, URL: p.WebURL})
	}
	ch.FailedPipelines = head(ch.FailedPipelines)
	return ch
}
