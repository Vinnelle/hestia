resource "kubernetes_namespace_v1" "chaos_mesh" {
  metadata {
    name = "chaos-mesh"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "chaos_mesh" {
  name       = "chaos-mesh"
  repository = "https://charts.chaos-mesh.org"
  chart      = "chaos-mesh"
  version    = "2.8.4"
  namespace  = kubernetes_namespace_v1.chaos_mesh.metadata[0].name

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

resource "kubectl_manifest" "chaos_pod_kill_websites" {
  depends_on = [helm_release.chaos_mesh]
  yaml_body = yamlencode({
    apiVersion = "chaos-mesh.org/v1alpha1"
    kind       = "Schedule"
    metadata = {
      name      = "pod-kill-websites"
      namespace = kubernetes_namespace_v1.chaos_mesh.metadata[0].name
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
          namespaces = ["websites"]
        }
      }
    }
  })
}

resource "kubectl_manifest" "chaos_stress_websites" {
  depends_on = [helm_release.chaos_mesh]
  yaml_body = yamlencode({
    apiVersion = "chaos-mesh.org/v1alpha1"
    kind       = "Schedule"
    metadata = {
      name      = "stress-websites"
      namespace = kubernetes_namespace_v1.chaos_mesh.metadata[0].name
    }
    spec = {
      schedule          = "0 * * * *"
      concurrencyPolicy = "Forbid"
      historyLimit      = 5
      type              = "StressChaos"
      stressChaos = {
        mode = "one"
        selector = {
          namespaces = ["websites"]
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
