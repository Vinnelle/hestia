resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = var.observability_namespace

  values = [
    yamlencode({
      args      = ["--kubelet-insecure-tls"]
      resources = { requests = { memory = "128Mi" }, limits = { memory = "256Mi" } }
    })
  ]
}

resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = "5.1.0"
  namespace  = var.platform_namespace

  values = [
    yamlencode({
      recommender = {
        enabled   = true
        extraArgs = { "pod-recommendation-min-memory-mb" = 32 }
        resources = { requests = { memory = "64Mi" }, limits = { memory = "512Mi" } }
      }
      updater = {
        enabled   = true
        extraArgs = { "min-replicas" = "1" }
        resources = { requests = { memory = "64Mi" }, limits = { memory = "512Mi" } }
      }
      admissionController = {
        enabled   = true
        resources = { requests = { memory = "64Mi" }, limits = { memory = "256Mi" } }
      }
    })
  ]

  depends_on = [helm_release.metrics_server]
}
