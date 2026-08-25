# SigNoz dashboards

The JSON files here are **not** the source of truth for what these dashboards show
(updated 2026-08-23). They were created through SigNoz's older `/api/v1/dashboards` REST API
back when the `signoz_dashboard` resource's typed v2/Perses schema needed a SigNoz version
that did not exist yet; the chart has since moved to `0.138.0` and the `restapi_object`
resources were adopted by `signoz_dashboard.dashboard`, which carries their IDs with
`ignore_changes = [spec, tags, name]`. Terraform reads each file only for its `title` and
`tags` — the panels live in SigNoz itself. Editing a file here changes nothing.

New dashboards do not go through this directory at all: write them as their own
`signoz_dashboard` resource with a real `spec` (`schema_version = "v6"`, panels keyed by UUID,
a `layouts` grid referencing them). `signoz_dashboard.service_status` and
`.container_security` in `main.tf` here are the two worked examples —
both use `builder_query` on metric names rather than PromQL, which is what the provider
validates at plan time. Porting one of the 22 below means giving it a real `spec` the same way
and removing its key from `local.signoz_dashboard_ids`.

Most files are official templates from [SigNoz/dashboards](https://github.com/SigNoz/dashboards).
`chaos-mesh/` is hand-written — no official template exists for it.

| File | Covers | Needs |
|---|---|---|
| `k8s-infra-metrics/kubernetes-cluster-metrics.json` | Cluster-wide health/uptime | k8s-infra (already deployed) |
| `k8s-infra-metrics/kubernetes-node-metrics-overall.json` + `-detailed.json` | Node performance | k8s-infra |
| `k8s-infra-metrics/kubernetes-pod-metrics-overall.json` + `-detailed.json` | Pod performance | k8s-infra |
| `k8s-infra-metrics/kubernetes-pvc-metrics.json` | Storage (local-path PVCs) | k8s-infra |
| `k8s-infra-metrics/kubernetes-cronjobs.json` | CronJob activity (pv-backup) | k8s-infra |
| `k8s-infra-metrics/k8s-events-receiver.json` | Cluster event stream (activity) | k8s-infra's `presets.kubernetesEvents` (already on) |
| `k8s-infra-metrics/host-metrics.json` | Raw host CPU/mem/disk/net | k8s-infra's `presets.hostMetrics` (already on) |
| `k8s-system-monitoring/kubernetes-system-overview.json` | Control-plane at a glance | k8s-infra |
| `k8s-system-monitoring/kubernetes-{apiserver,controller-manager,coredns,etcd,kube-proxy,kubelet,scheduler}.json` | Per-component control-plane detail | the 7 `presets.prometheus.scrapeConfigs` jobs in `helm-values/k8s-infra/values.yaml.tftpl`, the `extraArgs` in `talos/controlplane-patch.yaml`, the `control-plane-metrics-from-pods` firewall rule, and `kubernetes_cluster_role_v1.otel_agent_metrics` — all four are required together |
| `nginx/ingress-nginx-controller.json` | Web traffic (ingress-nginx) | the `prometheus.io/scrape` annotations already on `helm-values/ingress-nginx/values.yaml` |
| `nginx/nginx-ingress-request-handling-performance.json` | Ingress latency/perf detail | same |
| `cert-manager/cert-manager-dashboard.json` | Certificate lifecycle | nothing — cert-manager's chart adds `prometheus.io` annotations itself whenever `prometheus.enabled: true` and no ServiceMonitor is asked for, which is this cluster's config |
| `opentelemetry-collector/opentelemetry-collector-dashboard.json` | Health of the ingestion pipeline itself (catches "SigNoz silently stopped receiving data") | k8s-infra's own collector |
| `chaos-mesh/chaos-mesh.json` | Chaos experiment lifecycle (phase/kind/namespace), emitted events, chaos-daemon injection health | the `prometheus.io/scrape` annotations on `controllerManager`/`chaosDaemon` in `platform/chaos-mesh` |

**Not covered, deliberately:** internal pod-to-pod traffic (Cilium/Hubble) — Hubble already
has its own UI at `hubble.vinnel.cloud`, a second dashboard for the same data via a metrics
pipeline wasn't worth building. ARC runners / Harbor — no official templates exist;
build custom ones later if wanted, same path `chaos-mesh/` took.

A few panels in the control-plane and cert-manager dashboards query metric names that are **not
exclusive to the component the dashboard is named after** — `workqueue_*`, `go_goroutines`,
`process_resident_memory_bytes`, `rest_client_requests_total`, `controller_runtime_webhook_*`.
Every Go controller in the cluster exports those, so use each dashboard's `service.name`
variable to pin the component rather than trusting an unfiltered panel; the scrape jobs give
each control-plane component its own `service.name`, but annotation-discovered pods (ARC,
cert-manager, Cilium, Rook) all share `signoz-scraper`.

Some panels may still render empty until their underlying metric is actually flowing — that's
expected, not a sign the import failed.
