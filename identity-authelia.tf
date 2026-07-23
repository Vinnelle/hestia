
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

resource "random_password" "vinnel_cloud_dashboard_oidc_client_secret" {
  length  = 48
  special = false
}

resource "random_password" "vinnel_cloud_dashboard_cookie_secret" {
  length  = 64
  special = false
}

resource "tls_private_key" "authelia_oidc_issuer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

locals {
  authelia_configuration_yaml = templatefile("${path.module}/authelia/configuration.yml.tftpl", {
    session_secret                       = random_password.authelia_session_secret.result
    storage_encryption_key               = random_password.authelia_storage_encryption_key.result
    oidc_hmac_secret                     = random_password.authelia_oidc_hmac_secret.result
    oidc_issuer_private_key              = tls_private_key.authelia_oidc_issuer.private_key_pem_pkcs8
    netbird_dashboard_client_secret      = random_password.netbird_dashboard_oidc_client_secret.bcrypt_hash
    vinnel_cloud_dashboard_client_secret = random_password.vinnel_cloud_dashboard_oidc_client_secret.bcrypt_hash
  })

  authelia_users_database_yaml = templatefile("${path.module}/authelia/users_database.yml.tftpl", {
    admin_password_hash = random_password.authelia_admin_password.bcrypt_hash
  })
}

resource "kubernetes_secret_v1" "authelia_config" {
  metadata {
    name      = "authelia-config"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  data = {
    "configuration.yml" = local.authelia_configuration_yaml
  }
}

resource "kubernetes_secret_v1" "authelia_users_database" {
  metadata {
    name      = "authelia-users-database"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  data = {
    "users_database.yml" = local.authelia_users_database_yaml
  }
}

resource "kubernetes_persistent_volume_claim_v1" "authelia" {
  metadata {
    name      = "authelia-pvc"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
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
    namespace = kubernetes_namespace_v1.services.metadata[0].name
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
      }
    }
  }
}

resource "kubectl_manifest" "authelia_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.authelia]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "authelia"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.authelia.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "authelia", min_memory = "64Mi", max_memory = "256Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "authelia" {
  metadata {
    name      = "authelia"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
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
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
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
        path {
          path      = "/"
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
