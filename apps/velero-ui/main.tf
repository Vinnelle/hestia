resource "cloudflare_dns_record" "velero_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "velero.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "velero_ui_oidc_client_secret" {
  length  = 32
  special = false
}

resource "random_password" "velero_ui_auth_secret_passphrase" {
  length  = 64
  special = false
}

resource "kubernetes_service_account_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = var.namespace
  }
}

resource "kubernetes_cluster_role_v1" "velero_ui" {
  metadata {
    name = "velero-ui"
  }

  rule {
    non_resource_urls = ["/readyz", "/healthz", "/livez", "/version"]
    verbs             = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "velero_ui" {
  metadata {
    name = "velero-ui"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.velero_ui.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.velero_ui.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_role_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = var.namespace
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "pods/status", "secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["velero.io"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.velero_ui.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.velero_ui.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_config_map_v1" "velero_ui_policies" {
  metadata {
    name      = "velero-ui-policies"
    namespace = var.namespace
  }
  data = {
    "policies.csv" = "u,*,manage,all\n"
  }
}

resource "kubernetes_deployment_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = var.namespace
    labels = {
      app = "velero-ui"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "velero-ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "velero-ui"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "3000"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.velero_ui.metadata[0].name

        container {
          name  = "velero-ui"
          image = "otwld/velero-ui:0.10.2"

          port {
            name           = "http"
            container_port = 3000
          }

          env {
            name  = "VELERO_NAMESPACE"
            value = var.namespace
          }

          env {
            name  = "VELERO_UI_NAMESPACE"
            value = var.namespace
          }

          env {
            name  = "POLICY_FILE_PATH"
            value = "/policies/policies.csv"
          }

          env {
            name  = "BASE_URL"
            value = "https://velero.vinnel.cloud"
          }

          env {
            name = "AUTH_SECRET_PASSPHRASE"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.velero_ui_secrets.metadata[0].name
                key  = "auth-secret-passphrase"
              }
            }
          }

          env {
            name  = "BASIC_AUTH_ENABLED"
            value = "false"
          }

          env {
            name  = "OAUTH_AUTH_ENABLED"
            value = "true"
          }

          env {
            name  = "OAUTH_NAME"
            value = "Authelia"
          }

          env {
            name  = "OAUTH_AUTHORIZATION_URL"
            value = "https://auth.vinnel.cloud/api/oidc/authorization"
          }

          env {
            name  = "OAUTH_TOKEN_URL"
            value = "https://auth.vinnel.cloud/api/oidc/token"
          }

          env {
            name  = "OAUTH_USER_INFO_URL"
            value = "https://auth.vinnel.cloud/api/oidc/userinfo"
          }

          env {
            name  = "OAUTH_CLIENT_ID"
            value = "velero-ui"
          }

          env {
            name = "OAUTH_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.velero_ui_secrets.metadata[0].name
                key  = "oauth-client-secret"
              }
            }
          }

          env {
            name  = "OAUTH_OAUTH_SCOPE"
            value = "openid profile email"
          }

          env {
            name  = "OAUTH_REDIRECT_URI"
            value = "https://velero.vinnel.cloud/login"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "policies"
            mount_path = "/policies"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "policies"
          config_map {
            name = kubernetes_config_map_v1.velero_ui_policies.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_secret_v1" "velero_ui_secrets" {
  metadata {
    name      = "velero-ui-secrets"
    namespace = var.namespace
  }
  data = {
    "oauth-client-secret"    = random_password.velero_ui_oidc_client_secret.result
    "auth-secret-passphrase" = random_password.velero_ui_auth_secret_passphrase.result
  }
}

module "velero_ui_vpa" {
  source = "../../modules/vpa"

  depends_on = [kubernetes_deployment_v1.velero_ui]

  name        = "velero-ui"
  namespace   = var.namespace
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.velero_ui.metadata[0].name
  update_mode = "Auto"
  container_policies = [
    { container_name = "velero-ui", min_memory = "64Mi", max_memory = "256Mi" },
  ]
}

resource "kubernetes_service_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = var.namespace
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "velero-ui"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "velero_vinnel_cloud" {
  metadata {
    name      = "velero-vinnel-cloud"
    namespace = var.namespace
    annotations = merge(var.admin_frame_service_annotations, {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["velero.vinnel.cloud"]
      secret_name = "velero-vinnel-cloud-tls"
    }

    rule {
      host = "velero.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.velero_ui.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
