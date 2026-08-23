locals {
  chaos_site_namespaces = sort(tolist(toset([
    kubernetes_namespace_v1.vin_moe.metadata[0].name,
    kubernetes_namespace_v1.monke_academy.metadata[0].name,
    kubernetes_namespace_v1.vinnel_cloud.metadata[0].name,
  ])))
}

resource "helm_release" "chaos_mesh" {
  name       = "chaos-mesh"
  repository = "https://charts.chaos-mesh.org"
  chart      = "chaos-mesh"
  version    = "2.8.4"
  namespace  = kubernetes_namespace_v1.platform.metadata[0].name

  values = [
    yamlencode({
      controllerManager = {
        podAnnotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "10080"
        }
      }
      chaosDaemon = {
        runtime    = "containerd"
        socketPath = "/run/containerd/containerd.sock"
        podAnnotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "31766"
        }
      }
      dashboard = {
        service = { type = "ClusterIP" }
      }
    })
  ]
}

resource "kubectl_manifest" "chaos_pod_kill_sites" {
  depends_on = [helm_release.chaos_mesh]
  yaml_body = yamlencode({
    apiVersion = "chaos-mesh.org/v1alpha1"
    kind       = "Schedule"
    metadata = {
      name      = "pod-kill-sites"
      namespace = kubernetes_namespace_v1.platform.metadata[0].name
    }
    spec = {
      schedule          = "*/30 * * * *"
      concurrencyPolicy = "Forbid"
      historyLimit      = 5
      type              = "PodChaos"
      podChaos = {
        action = "pod-kill"
        mode   = "one"
        selector = {
          namespaces = local.chaos_site_namespaces
        }
      }
    }
  })
}

resource "kubectl_manifest" "chaos_stress_sites" {
  depends_on = [helm_release.chaos_mesh]
  yaml_body = yamlencode({
    apiVersion = "chaos-mesh.org/v1alpha1"
    kind       = "Schedule"
    metadata = {
      name      = "stress-sites"
      namespace = kubernetes_namespace_v1.platform.metadata[0].name
    }
    spec = {
      schedule          = "0 * * * *"
      concurrencyPolicy = "Forbid"
      historyLimit      = 5
      type              = "StressChaos"
      stressChaos = {
        mode = "one"
        selector = {
          namespaces = local.chaos_site_namespaces
        }
        stressors = {
          cpu    = { workers = 1, load = 50 }
          memory = { workers = 1, size = "128MB" }
        }
        duration = "5m"
      }
    }
  })
}
