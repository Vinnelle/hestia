resource "kubernetes_deployment_v1" "netbird_dashboard" {
  metadata {
    name      = "netbird-dashboard"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    labels = {
      app = "netbird-dashboard"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "netbird-dashboard"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "netbird-dashboard"
        }
      }

      spec {
        container {
          name  = "dashboard"
          image = "netbirdio/dashboard:v2.90.3"

          env {
            name  = "NETBIRD_MGMT_API_ENDPOINT"
            value = "https://proxy.vinnel.cloud"
          }

          env {
            name  = "NETBIRD_MGMT_GRPC_API_ENDPOINT"
            value = "https://proxy.vinnel.cloud"
          }

          env {
            name  = "AUTH_AUDIENCE"
            value = "netbird-dashboard"
          }

          env {
            name  = "AUTH_CLIENT_ID"
            value = "netbird-dashboard"
          }

          env {
            name = "AUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.netbird_secrets.metadata[0].name
                key  = "dashboard-oidc-client-secret"
              }
            }
          }

          env {
            name  = "AUTH_AUTHORITY"
            value = "https://auth.vinnel.cloud"
          }

          env {
            name  = "USE_AUTH0"
            value = "false"
          }

          env {
            name  = "AUTH_SUPPORTED_SCOPES"
            value = "openid profile email offline_access"
          }

          env {
            name  = "AUTH_REDIRECT_URI"
            value = "/nb-auth"
          }

          env {
            name  = "AUTH_SILENT_REDIRECT_URI"
            value = "/nb-silent-auth"
          }

          env {
            name  = "NETBIRD_TOKEN_SOURCE"
            value = "idToken"
          }

          env {
            name  = "LETSENCRYPT_DOMAIN"
            value = "none"
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
            http_get {
              path = "/"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            http_get {
              path = "/"
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

resource "kubectl_manifest" "netbird_dashboard_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.netbird_dashboard]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "netbird-dashboard"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.netbird_dashboard.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "dashboard", min_memory = "32Mi", max_memory = "128Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "netbird_dashboard" {
  metadata {
    name      = "netbird-dashboard"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "netbird-dashboard"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}
