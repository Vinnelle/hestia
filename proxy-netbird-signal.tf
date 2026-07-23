resource "kubernetes_deployment_v1" "netbird_signal" {
  metadata {
    name      = "netbird-signal"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    labels = {
      app = "netbird-signal"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "netbird-signal"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "netbird-signal"
        }
      }

      spec {
        container {
          name  = "signal"
          image = "netbirdio/signal:0.74.3"
          args  = ["--port", "80", "--log-file", "console"]

          port {
            name           = "http"
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "netbird_signal_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.netbird_signal]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "netbird-signal"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.netbird_signal.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "signal", min_memory = "32Mi", max_memory = "128Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "netbird_signal" {
  metadata {
    name      = "netbird-signal"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "netbird-signal"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}
