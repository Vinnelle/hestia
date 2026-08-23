resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name

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
  version    = "5.0.0"
  namespace  = kubernetes_namespace_v1.platform.metadata[0].name

  values = [
    yamlencode({
      recommender         = { enabled = true }
      updater             = { enabled = true, extraArgs = { "min-replicas" = "1" } }
      admissionController = { enabled = true }
    })
  ]

  depends_on = [helm_release.metrics_server]
}
