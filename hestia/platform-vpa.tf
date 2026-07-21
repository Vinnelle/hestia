resource "kubernetes_namespace_v1" "vpa" {
  metadata {
    name = "vpa"
  }
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.13.1"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    yamlencode({
      args = ["--kubelet-insecure-tls"]
    })
  ]
}

resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = "4.12.3"
  namespace  = kubernetes_namespace_v1.vpa.metadata[0].name

  values = [
    yamlencode({
      recommender         = { enabled = true }
      updater             = { enabled = true, extraArgs = { "min-replicas" = "1" } }
      admissionController = { enabled = true }
    })
  ]

  depends_on = [helm_release.metrics_server]
}
