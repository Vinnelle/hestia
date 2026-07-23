resource "kubernetes_deployment_v1" "netbird_relay" {
  metadata {
    name      = "netbird-relay"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    labels = {
      app = "netbird-relay"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "netbird-relay"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "netbird-relay"
        }
      }

      spec {
        container {
          name  = "relay"
          image = "netbirdio/relay:0.74.7"

          env {
            name  = "NB_LOG_LEVEL"
            value = "info"
          }

          env {
            name  = "NB_LISTEN_ADDRESS"
            value = ":80"
          }

          env {
            name  = "NB_EXPOSED_ADDRESS"
            value = "rels://proxy.vinnel.cloud/relay"
          }

          env {
            name = "NB_AUTH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.netbird_secrets.metadata[0].name
                key  = "relay-auth-secret"
              }
            }
          }

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

resource "kubectl_manifest" "netbird_relay_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.netbird_relay]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "netbird-relay"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.netbird_relay.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "relay", min_memory = "32Mi", max_memory = "128Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "netbird_relay" {
  metadata {
    name      = "netbird-relay"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "netbird-relay"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}
