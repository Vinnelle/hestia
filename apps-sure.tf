resource "kubernetes_namespace_v1" "sure" {
  metadata {
    name = "sure"
  }
}

resource "cloudflare_dns_record" "sure_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "sure.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "sure_secret_key_base" {
  length  = 64
  special = false
}

resource "random_password" "sure_postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "sure_redis_password" {
  length  = 32
  special = false
}

resource "random_password" "sure_encryption_primary_key" {
  length  = 32
  special = false
}

resource "random_password" "sure_encryption_deterministic_key" {
  length  = 32
  special = false
}

resource "random_password" "sure_encryption_key_derivation_salt" {
  length  = 32
  special = false
}

resource "random_password" "sure_oidc_client_secret" {
  length  = 48
  special = false
}

locals {
  sure_image = "ghcr.io/we-promise/sure@sha256:12361b7b309f867002b8a1f54200607ca1a321e1b57cf21890caaf83602c3cd0"

  sure_env = {
    RAILS_ENV           = "production"
    SELF_HOSTED         = "true"
    APP_DOMAIN          = "sure.vinnel.cloud"
    RAILS_LOG_TO_STDOUT = "true"
    OIDC_ISSUER         = "https://auth.vinnel.cloud"
    OIDC_CLIENT_ID      = "sure"
    OIDC_REDIRECT_URI   = "https://sure.vinnel.cloud/auth/openid_connect/callback"
    OIDC_BUTTON_LABEL   = "Sign in with Authelia"
  }

  sure_secret_env = {
    SECRET_KEY_BASE                              = "secret-key-base"
    DATABASE_URL                                 = "database-url"
    REDIS_URL                                    = "redis-url"
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY         = "encryption-primary-key"
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY   = "encryption-deterministic-key"
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT = "encryption-key-salt"
    OIDC_CLIENT_SECRET                           = "oidc-client-secret"
  }

  sure_config_hash = sha256(join("", [
    random_password.sure_secret_key_base.result,
    random_password.sure_postgres_password.result,
    random_password.sure_redis_password.result,
    random_password.sure_encryption_primary_key.result,
    random_password.sure_encryption_deterministic_key.result,
    random_password.sure_encryption_key_derivation_salt.result,
    random_password.sure_oidc_client_secret.result,
  ]))
}

resource "kubernetes_secret_v1" "sure_secrets" {
  metadata {
    name      = "sure-secrets"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
  }
  data = {
    "secret-key-base"              = random_password.sure_secret_key_base.result
    "postgres-password"            = random_password.sure_postgres_password.result
    "redis-password"               = random_password.sure_redis_password.result
    "database-url"                 = "postgresql://sure:${random_password.sure_postgres_password.result}@sure-postgres:5432/sure_production"
    "redis-url"                    = "redis://:${random_password.sure_redis_password.result}@sure-redis:6379/0"
    "encryption-primary-key"       = random_password.sure_encryption_primary_key.result
    "encryption-deterministic-key" = random_password.sure_encryption_deterministic_key.result
    "encryption-key-salt"          = random_password.sure_encryption_key_derivation_salt.result
    "oidc-client-secret"           = random_password.sure_oidc_client_secret.result
  }
}

resource "kubernetes_persistent_volume_claim_v1" "sure_postgres" {
  metadata {
    name      = "sure-postgres-pvc"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim_v1" "sure_storage" {
  metadata {
    name      = "sure-storage-pvc"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "sure_postgres" {
  metadata {
    name      = "sure-postgres"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
    labels = {
      app = "sure-postgres"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sure-postgres"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "sure-postgres"
        }
        annotations = {
          "config-hash" = local.sure_config_hash
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:17-alpine"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env {
            name  = "POSTGRES_USER"
            value = "sure"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.sure_secrets.metadata[0].name
                key  = "postgres-password"
              }
            }
          }

          env {
            name  = "POSTGRES_DB"
            value = "sure_production"
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "sure", "-d", "sure_production"]
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "sure", "-d", "sure_production"]
            }
            period_seconds  = 10
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.sure_postgres.metadata[0].name
          }
        }
      }
    }
  }
}

module "sure_postgres_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.sure_postgres]

  name        = "sure-postgres"
  namespace   = kubernetes_namespace_v1.sure.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.sure_postgres.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "postgres", min_memory = "256Mi", max_memory = "1Gi" },
  ]
}

resource "kubernetes_service_v1" "sure_postgres" {
  metadata {
    name      = "sure-postgres"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "sure-postgres"
    }
    port {
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_deployment_v1" "sure_redis" {
  metadata {
    name      = "sure-redis"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
    labels = {
      app = "sure-redis"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sure-redis"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "sure-redis"
        }
        annotations = {
          "config-hash" = local.sure_config_hash
        }
      }

      spec {
        container {
          name    = "redis"
          image   = "redis:7-alpine"
          command = ["redis-server", "--requirepass", "$(REDIS_PASSWORD)"]

          port {
            name           = "redis"
            container_port = 6379
          }

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.sure_secrets.metadata[0].name
                key  = "redis-password"
              }
            }
          }

          env {
            name = "REDISCLI_AUTH"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.sure_secrets.metadata[0].name
                key  = "redis-password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            period_seconds  = 5
            timeout_seconds = 3
          }

          liveness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            period_seconds  = 10
            timeout_seconds = 3
          }
        }
      }
    }
  }
}

module "sure_redis_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.sure_redis]

  name        = "sure-redis"
  namespace   = kubernetes_namespace_v1.sure.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.sure_redis.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "redis", min_memory = "128Mi", max_memory = "512Mi" },
  ]
}

resource "kubernetes_service_v1" "sure_redis" {
  metadata {
    name      = "sure-redis"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "sure-redis"
    }
    port {
      port        = 6379
      target_port = "redis"
    }
  }
}

resource "kubernetes_deployment_v1" "sure_web" {
  depends_on = [kubernetes_deployment_v1.sure_postgres, kubernetes_deployment_v1.sure_redis]

  metadata {
    name      = "sure-web"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
    labels = {
      app = "sure-web"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sure-web"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "sure-web"
        }
        annotations = {
          "config-hash" = local.sure_config_hash
        }
      }

      spec {
        security_context {
          fs_group = 1000
        }

        container {
          name  = "sure"
          image = local.sure_image

          port {
            name           = "http"
            container_port = 3000
          }

          dynamic "env" {
            for_each = local.sure_env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = local.sure_secret_env
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = kubernetes_secret_v1.sure_secrets.metadata[0].name
                  key  = env.value
                }
              }
            }
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "768Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "2Gi"
            }
          }

          volume_mount {
            name       = "storage"
            mount_path = "/rails/storage"
          }

          startup_probe {
            http_get {
              path = "/up"
              port = "http"
            }
            period_seconds    = 5
            failure_threshold = 60
          }

          readiness_probe {
            http_get {
              path = "/up"
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/up"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.sure_storage.metadata[0].name
          }
        }
      }
    }
  }
}

module "sure_web_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.sure_web]

  name        = "sure-web"
  namespace   = kubernetes_namespace_v1.sure.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.sure_web.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "sure", min_memory = "768Mi", max_memory = "2Gi" },
  ]
}

resource "kubernetes_deployment_v1" "sure_worker" {
  depends_on = [kubernetes_deployment_v1.sure_web]

  metadata {
    name      = "sure-worker"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
    labels = {
      app = "sure-worker"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "sure-worker"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "sure-worker"
        }
        annotations = {
          "config-hash" = local.sure_config_hash
        }
      }

      spec {
        security_context {
          fs_group = 1000
        }

        container {
          name    = "sidekiq"
          image   = local.sure_image
          command = ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]

          dynamic "env" {
            for_each = local.sure_env
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "env" {
            for_each = local.sure_secret_env
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = kubernetes_secret_v1.sure_secrets.metadata[0].name
                  key  = env.value
                }
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1536Mi"
            }
          }

          volume_mount {
            name       = "storage"
            mount_path = "/rails/storage"
          }
        }

        volume {
          name = "storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.sure_storage.metadata[0].name
          }
        }
      }
    }
  }
}

module "sure_worker_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.sure_worker]

  name        = "sure-worker"
  namespace   = kubernetes_namespace_v1.sure.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.sure_worker.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "sidekiq", min_memory = "512Mi", max_memory = "1536Mi" },
  ]
}

resource "kubernetes_service_v1" "sure_web" {
  metadata {
    name      = "sure-web"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "sure-web"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "sure_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "sure-vinnel-cloud"
    namespace = kubernetes_namespace_v1.sure.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "50m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["sure.vinnel.cloud"]
      secret_name = "sure-vinnel-cloud-tls"
    }

    rule {
      host = "sure.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.sure_web.metadata[0].name
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
