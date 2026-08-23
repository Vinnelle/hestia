resource "kubernetes_namespace_v1" "auth" {
  metadata {
    name = "auth"
  }
}

resource "cloudflare_dns_record" "auth_vin_moe" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "auth.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "authelia_session_secret" {
  length  = 64
  special = false
}

resource "random_password" "authelia_storage_encryption_key" {
  length  = 64
  special = false
}

resource "random_password" "authelia_oidc_hmac_secret" {
  length  = 64
  special = false
}

resource "random_password" "authelia_admin_password" {
  length  = 24
  special = true
}

resource "random_password" "netbird_dashboard_oidc_client_secret" {
  length  = 48
  special = false
}

resource "tls_private_key" "authelia_oidc_issuer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  authelia_configuration_yaml = templatefile("${path.module}/identity/authelia/configuration.yml.tftpl", {
    session_secret                  = random_password.authelia_session_secret.result
    storage_encryption_key          = random_password.authelia_storage_encryption_key.result
    oidc_hmac_secret                = random_password.authelia_oidc_hmac_secret.result
    oidc_issuer_private_key         = tls_private_key.authelia_oidc_issuer.private_key_pem_pkcs8
    netbird_dashboard_client_secret = random_password.netbird_dashboard_oidc_client_secret.bcrypt_hash
    velero_ui_client_secret         = random_password.velero_ui_oidc_client_secret.bcrypt_hash
    nextcloud_client_secret         = random_password.nextcloud_oidc_client_secret.bcrypt_hash
  })

  authelia_users_database_yaml = templatefile("${path.module}/identity/authelia/users_database.yml.tftpl", {
    admin_password_hash = random_password.authelia_admin_password.bcrypt_hash
  })
}

resource "kubernetes_secret_v1" "authelia_config" {
  metadata {
    name      = "authelia-config"
    namespace = kubernetes_namespace_v1.auth.metadata[0].name
  }
  data = {
    "configuration.yml" = local.authelia_configuration_yaml
  }
}

resource "kubernetes_secret_v1" "authelia_users_database" {
  metadata {
    name      = "authelia-users-database"
    namespace = kubernetes_namespace_v1.auth.metadata[0].name
  }
  data = {
    "users_database.yml" = local.authelia_users_database_yaml
  }
}

resource "kubernetes_secret_v1" "authelia_smtp_credentials" {
  metadata {
    name      = "authelia-smtp-credentials"
    namespace = kubernetes_namespace_v1.auth.metadata[0].name
  }
  data = {
    "smtp-password" = var.resend_api_key
  }
}

resource "kubernetes_persistent_volume_claim_v1" "authelia" {
  metadata {
    name      = "authelia-pvc"
    namespace = kubernetes_namespace_v1.auth.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace_v1.auth.metadata[0].name
    labels = {
      app = "authelia"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "authelia"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "authelia"
        }
        annotations = {
          "checksum/config"         = sha256(local.authelia_configuration_yaml)
          "checksum/users-database" = sha256(local.authelia_users_database_yaml)
          "checksum/smtp-password"  = sha256(var.resend_api_key)
          "prometheus.io/scrape"    = "true"
          "prometheus.io/port"      = "9959"
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "authelia"
          image = "authelia/authelia:4.39.20"

          port {
            name           = "http"
            container_port = 9091
          }

          port {
            name           = "metrics"
            container_port = 9959
          }

          env {
            name  = "AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE"
            value = "/secrets/smtp-password"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config/configuration.yml"
            sub_path   = "configuration.yml"
            read_only  = true
          }

          volume_mount {
            name       = "users-database"
            mount_path = "/config/users_database.yml"
            sub_path   = "users_database.yml"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/config/data"
          }

          volume_mount {
            name       = "smtp-password"
            mount_path = "/secrets/smtp-password"
            sub_path   = "smtp-password"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = "9091"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = "9091"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.authelia_config.metadata[0].name
          }
        }

        volume {
          name = "users-database"
          secret {
            secret_name = kubernetes_secret_v1.authelia_users_database.metadata[0].name
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.authelia.metadata[0].name
          }
        }

        volume {
          name = "smtp-password"
          secret {
            secret_name = kubernetes_secret_v1.authelia_smtp_credentials.metadata[0].name
          }
        }
      }
    }
  }
}

module "authelia_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.authelia]

  name        = "authelia"
  namespace   = kubernetes_namespace_v1.auth.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.authelia.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "authelia", min_memory = "64Mi", max_memory = "256Mi" },
  ]
}

resource "kubernetes_service_v1" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace_v1.auth.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "authelia"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "authelia" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace_v1.auth.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer

      "nginx.ingress.kubernetes.io/server-snippet" = <<-EOT
        location = /brand.css {
          default_type text/css;
          expires 1h;
          return 200 ":root{color-scheme:light dark;
            --bg:light-dark(#faf8f5,#0c0c0d);
            --fg:light-dark(#2a2825,#cececa);
            --muted:light-dark(#4a4743,#a9a9a3);
            --dim:light-dark(#625e57,#74746f);
            --accent:light-dark(#b3466b,#f7b9d1);
            --accent-strong:light-dark(#8f3355,#fbd3e2);}
          *{font-family:'JetBrains Mono',ui-monospace,'SF Mono',Menlo,Consolas,'Liberation Mono',monospace !important;}
          html,body,#root{background:var(--bg) !important;color:var(--fg) !important;}
          .MuiPaper-root{background:transparent !important;background-image:none !important;box-shadow:none !important;color:var(--fg) !important;}
          .MuiTypography-root{color:var(--fg) !important;}
          .MuiTypography-h5{text-transform:lowercase;letter-spacing:-0.01em;}
          .MuiAvatar-root{display:none !important;}
          .MuiFormLabel-root{color:var(--dim) !important;}
          .MuiFormLabel-root.Mui-focused{color:var(--accent) !important;}
          .MuiInputBase-input{color:var(--fg) !important;}
          .MuiOutlinedInput-notchedOutline{border-color:var(--dim) !important;border-radius:2px;}
          .Mui-focused .MuiOutlinedInput-notchedOutline{border-color:var(--accent) !important;}
          .MuiSvgIcon-root{color:var(--dim);}
          .MuiButton-contained{background:var(--accent) !important;color:var(--bg) !important;box-shadow:none !important;border-radius:2px;text-transform:lowercase !important;}
          .MuiButton-contained:hover{background:var(--accent-strong) !important;}
          .MuiButton-text{color:var(--accent) !important;text-transform:lowercase !important;}
          .MuiCheckbox-root{color:var(--dim) !important;}
          .MuiCheckbox-root.Mui-checked{color:var(--accent) !important;}
          a{color:var(--accent) !important;}
          a:hover{color:var(--accent-strong) !important;}";
        }
      EOT

      "nginx.ingress.kubernetes.io/configuration-snippet" = <<-EOT
        more_clear_headers "X-Frame-Options";
        more_clear_headers "Content-Security-Policy";
        proxy_set_header Accept-Encoding "";
        sub_filter '</head>' '<link rel="stylesheet" href="./brand.css" /></head>';
        sub_filter_once on;
      EOT
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["auth.vinnel.cloud"]
      secret_name = "authelia-tls"
    }

    rule {
      host = "auth.vinnel.cloud"
      http {
        dynamic "path" {
          for_each = ["/api", "/consent", "/settings", "/static", "/locales", "/jwks.json", "/.well-known", "/device", "/reset-password"]
          content {
            path      = path.value
            path_type = "Prefix"
            backend {
              service {
                name = kubernetes_service_v1.authelia.metadata[0].name
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
}
