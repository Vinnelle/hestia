
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "7.0.0"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    file("${path.module}/helm-values/loki/values.yaml")
  ]
}

resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.17.1"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/promtail/values.yaml.tftpl", {
      monitoring_namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    })
  ]

  depends_on = [helm_release.loki]
}

resource "grafana_data_source" "loki" {
  type = "loki"
  name = "Loki"
  uid  = "loki"
  url  = "http://loki.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local:3100"

  depends_on = [helm_release.loki]
}
