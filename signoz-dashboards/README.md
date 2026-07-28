# SigNoz dashboards

Not Terraform-managed — `signoz_dashboard` needs SigNoz >= v0.135.0 (the typed v2/Perses
schema this repo's `signoz` provider targets), and that version doesn't exist yet
(checked SigNoz's actual GitHub releases 2026-07-28: v0.134.0, the version this cluster
runs, is current). Blocked upstream, not a config problem here.

These are official templates from [SigNoz/dashboards](https://github.com/SigNoz/dashboards)
instead — a different, older JSON schema that SigNoz's UI import has supported since
before v2 existed, so it works today. Import each by hand: SigNoz UI -> Dashboards ->
New dashboard -> Import JSON -> upload the file. Re-import (same name) to pick up updates
pulled from upstream later.

| File | Covers | Needs |
|---|---|---|
| `k8s-infra-metrics/kubernetes-cluster-metrics.json` | Cluster-wide health/uptime | k8s-infra (already deployed) |
| `k8s-infra-metrics/kubernetes-node-metrics-overall.json` + `-detailed.json` | Node performance | k8s-infra |
| `k8s-infra-metrics/kubernetes-pod-metrics-overall.json` + `-detailed.json` | Pod performance | k8s-infra |
| `k8s-infra-metrics/kubernetes-pvc-metrics.json` | Storage (local-path + Ceph PVCs) | k8s-infra |
| `k8s-infra-metrics/kubernetes-cronjobs.json` | CronJob activity (pv-backup) | k8s-infra |
| `k8s-infra-metrics/k8s-events-receiver.json` | Cluster event stream (activity) | k8s-infra's `presets.kubernetesEvents` (already on) |
| `k8s-infra-metrics/host-metrics.json` | Raw host CPU/mem/disk/net | k8s-infra's `presets.hostMetrics` (already on) |
| `hostmetrics/hostmetrics-k8s.json` | Host metrics, k8s-labeled variant | same |
| `k8s-system-monitoring/kubernetes-system-overview.json` | Control-plane at a glance | k8s-infra |
| `k8s-system-monitoring/kubernetes-{apiserver,controller-manager,coredns,etcd,kube-proxy,kubelet,scheduler}.json` | Per-component control-plane detail | k8s-infra; some need those components' own `/metrics` scraped — not verified reachable on this Talos cluster, check for empty panels |
| `nginx/ingress-nginx-controller.json` | Web traffic (ingress-nginx) | the `prometheus.io/scrape` annotations already on `helm-values/ingress-nginx/values.yaml` |
| `nginx/nginx-ingress-request-handling-performance.json` | Ingress latency/perf detail | same |
| `cert-manager/cert-manager-dashboard.json` | Certificate lifecycle | cert-manager's own metrics port — not verified scraped, check for empty panels |
| `opentelemetry-collector/opentelemetry-collector-dashboard.json` | Health of the ingestion pipeline itself (catches "SigNoz silently stopped receiving data") | k8s-infra's own collector |

**Not covered, deliberately:** internal pod-to-pod traffic (Cilium/Hubble) — Hubble already
has its own UI at `hubble.vinnel.cloud`, a second dashboard for the same data via a metrics
pipeline wasn't worth building. ARC runners / Harbor / Ceph — no official templates exist;
build custom ones later if wanted, same JSON-import path.

Some panels may render empty until their underlying metric is actually flowing (control-plane
component scrape targets in particular aren't verified) — that's expected, not a sign the
import failed.
