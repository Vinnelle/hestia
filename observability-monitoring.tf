
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = "29.19.0"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    file("${path.module}/helm-values/prometheus/values.yaml")
  ]
}

resource "grafana_data_source" "prometheus" {
  type       = "prometheus"
  name       = "Prometheus"
  uid        = "prometheus"
  url        = "http://prometheus-server.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local"
  is_default = true

  depends_on = [helm_release.prometheus]
}

resource "grafana_folder" "infrastructure" {
  title = "Infrastructure"
}

locals {
  prometheus_ds = {
    type = "prometheus"
    uid  = grafana_data_source.prometheus.uid
  }
}
