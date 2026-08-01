resource "cloudflare_dns_record" "velero_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
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
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
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
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
  }
}

resource "kubernetes_role_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
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
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.velero_ui.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.velero_ui.metadata[0].name
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "velero_ui_policies" {
  metadata {
    name      = "velero-ui-policies"
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
  }
  data = {
    "policies.csv" = "u,*,manage,all\n"
  }
}

resource "kubernetes_deployment_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
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
            value = kubernetes_namespace_v1.velero.metadata[0].name
          }

          env {
            name  = "VELERO_UI_NAMESPACE"
            value = kubernetes_namespace_v1.velero.metadata[0].name
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
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
  }
  data = {
    "oauth-client-secret"    = random_password.velero_ui_oidc_client_secret.result
    "auth-secret-passphrase" = random_password.velero_ui_auth_secret_passphrase.result
  }
}

resource "kubectl_manifest" "velero_ui_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.velero_ui]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "velero-ui"
    namespace   = kubernetes_namespace_v1.velero.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.velero_ui.metadata[0].name
    update_mode = "Auto"
    container_policies = [
      { container_name = "velero-ui", min_memory = "64Mi", max_memory = "256Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "velero_ui" {
  metadata {
    name      = "velero-ui"
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
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
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "velero-vinnel-cloud"
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
    annotations = merge(local.admin_framed_service_annotations["velero"], {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    })
  }

  spec {
    ingress_class_name = "nginx"

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
