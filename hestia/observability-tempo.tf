
resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.24.4"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    file("${path.module}/helm-values/tempo/values.yaml")
  ]
}

resource "grafana_data_source" "tempo" {
  type = "tempo"
  name = "Tempo"
  uid  = "tempo"
  url  = "http://tempo.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local:3200"

  depends_on = [helm_release.tempo]
}
