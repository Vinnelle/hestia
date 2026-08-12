
resource "kubernetes_namespace_v1" "worldwideview" {
  metadata {
    name = "worldwideview"
  }
}

resource "cloudflare_dns_record" "wwv_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "wwv.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "wwv_engine_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "wwv-engine.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "wwv_better_auth_secret" {
  length  = 64
  special = false
}

resource "random_password" "wwv_encryption_master_key" {
  length  = 32
  special = false
}

resource "random_password" "wwv_cross_service_secret" {
  length  = 64
  special = false
}

resource "random_password" "wwv_redis_password" {
  length  = 64
  special = false
}

resource "random_password" "wwv_postgres_password" {
  length  = 32
  special = false
}

locals {
  wwv_config_hash = sha256(join("", [
    random_password.wwv_better_auth_secret.result,
    random_password.wwv_encryption_master_key.result,
    random_password.wwv_cross_service_secret.result,
    random_password.wwv_redis_password.result,
    random_password.wwv_postgres_password.result,
    var.wwv_cesium_ion_token,
    var.wwv_bing_maps_key,
    var.wwv_openweathermap_api_key,
    var.wwv_acled_email,
    var.wwv_acled_password,
  ]))
}

resource "kubernetes_secret_v1" "wwv_secrets" {
  metadata {
    name      = "wwv-secrets"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
  }
  data = {
    "better-auth-secret"     = random_password.wwv_better_auth_secret.result
    "encryption-master-key"  = random_password.wwv_encryption_master_key.result
    "cross-service-secret"   = random_password.wwv_cross_service_secret.result
    "redis-password"         = random_password.wwv_redis_password.result
    "postgres-password"      = random_password.wwv_postgres_password.result
    "cesium-ion-token"       = var.wwv_cesium_ion_token
    "bing-maps-key"          = var.wwv_bing_maps_key
    "openweathermap-api-key" = var.wwv_openweathermap_api_key
    "acled-email"            = var.wwv_acled_email
    "acled-password"         = var.wwv_acled_password
  }
}

resource "kubernetes_persistent_volume_claim_v1" "wwv_postgres" {
  metadata {
    name      = "wwv-postgres-pvc"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
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

resource "kubernetes_persistent_volume_claim_v1" "wwv_app_data" {
  metadata {
    name      = "wwv-app-data-pvc"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
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

resource "kubernetes_persistent_volume_claim_v1" "wwv_engine_data" {
  metadata {
    name      = "wwv-engine-data-pvc"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
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

resource "kubernetes_deployment_v1" "wwv_postgres" {
  metadata {
    name      = "wwv-postgres"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
    labels = {
      app = "wwv-postgres"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wwv-postgres"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "wwv-postgres"
        }
        annotations = {
          "config-hash" = local.wwv_config_hash
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:15-alpine"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env {
            name  = "POSTGRES_USER"
            value = "postgres"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "postgres-password"
              }
            }
          }

          env {
            name  = "POSTGRES_DB"
            value = "worldwideview"
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
              command = ["pg_isready", "-U", "postgres", "-d", "worldwideview"]
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-d", "worldwideview"]
            }
            period_seconds  = 10
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.wwv_postgres.metadata[0].name
          }
        }
      }
    }
  }
}

module "wwv_postgres_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.wwv_postgres]

  name        = "wwv-postgres"
  namespace   = kubernetes_namespace_v1.worldwideview.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.wwv_postgres.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "postgres", min_memory = "256Mi", max_memory = "1Gi" },
  ]
}

resource "kubernetes_service_v1" "wwv_postgres" {
  metadata {
    name      = "wwv-postgres"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "wwv-postgres"
    }
    port {
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_deployment_v1" "wwv_redis" {
  metadata {
    name      = "wwv-redis"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
    labels = {
      app = "wwv-redis"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wwv-redis"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "wwv-redis"
        }
        annotations = {
          "config-hash" = local.wwv_config_hash
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
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "redis-password"
              }
            }
          }

          env {
            name = "REDISCLI_AUTH"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
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

module "wwv_redis_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.wwv_redis]

  name        = "wwv-redis"
  namespace   = kubernetes_namespace_v1.worldwideview.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.wwv_redis.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "redis", min_memory = "128Mi", max_memory = "512Mi" },
  ]
}

resource "kubernetes_service_v1" "wwv_redis" {
  metadata {
    name      = "wwv-redis"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "wwv-redis"
    }
    port {
      port        = 6379
      target_port = "redis"
    }
  }
}

resource "kubernetes_deployment_v1" "wwv_data_engine" {
  metadata {
    name      = "wwv-data-engine"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
    labels = {
      app = "wwv-data-engine"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wwv-data-engine"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "wwv-data-engine"
        }
        annotations = {
          "config-hash" = local.wwv_config_hash
        }
      }

      spec {
        container {
          name              = "wwv-data-engine"
          image             = "ghcr.io/silvertakana/wwv-data-engine:latest"
          image_pull_policy = "Always"

          port {
            name           = "http"
            container_port = 5000
          }

          env {
            name  = "PORT"
            value = "5000"
          }

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "redis-password"
              }
            }
          }

          env {
            name  = "REDIS_URL"
            value = "redis://:$(REDIS_PASSWORD)@wwv-redis:6379"
          }

          env {
            name  = "DOWNLOAD_SEEDERS"
            value = "true"
          }

          env {
            name  = "DB_PATH"
            value = "/app/data/engine.db"
          }

          env {
            name  = "WWV_SKIP_WS_AUTH"
            value = "true"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1536Mi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/app/data"
          }

          startup_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds    = 10
            failure_threshold = 30
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.wwv_engine_data.metadata[0].name
          }
        }
      }
    }
  }
}

module "wwv_data_engine_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.wwv_data_engine]

  name        = "wwv-data-engine"
  namespace   = kubernetes_namespace_v1.worldwideview.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.wwv_data_engine.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "wwv-data-engine", min_memory = "512Mi", max_memory = "1536Mi" },
  ]
}

resource "kubernetes_service_v1" "wwv_data_engine" {
  metadata {
    name      = "wwv-data-engine"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "wwv-data-engine"
    }
    port {
      port        = 5000
      target_port = "http"
    }
  }
}

resource "kubernetes_deployment_v1" "wwv" {
  depends_on = [kubernetes_deployment_v1.wwv_postgres, kubernetes_deployment_v1.wwv_redis]

  metadata {
    name      = "wwv"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
    labels = {
      app = "wwv"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "wwv"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "wwv"
        }
        annotations = {
          "config-hash" = local.wwv_config_hash
        }
      }

      spec {
        container {
          name              = "wwv"
          image             = "ghcr.io/silvertakana/worldwideview:latest"
          image_pull_policy = "Always"

          port {
            name           = "http"
            container_port = 3000
          }

          env {
            name  = "NEXT_PUBLIC_WWV_EDITION"
            value = "local"
          }

          env {
            name = "BETTER_AUTH_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "better-auth-secret"
              }
            }
          }

          env {
            name = "ENCRYPTION_MASTER_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "encryption-master-key"
              }
            }
          }

          env {
            name = "CROSS_SERVICE_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "cross-service-secret"
              }
            }
          }

          env {
            name = "REDIS_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "redis-password"
              }
            }
          }

          env {
            name  = "REDIS_URL"
            value = "redis://:$(REDIS_PASSWORD)@wwv-redis:6379"
          }

          env {
            name = "WWV_POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "postgres-password"
              }
            }
          }

          env {
            name  = "DATABASE_URL"
            value = "postgresql://postgres:$(WWV_POSTGRES_PASSWORD)@wwv-postgres:5432/worldwideview?schema=public"
          }

          env {
            name  = "WWV_DATA_ENGINE_URL"
            value = "http://wwv-data-engine.${kubernetes_namespace_v1.worldwideview.metadata[0].name}.svc.cluster.local:5000"
          }

          env {
            name  = "NEXT_PUBLIC_WWV_PLUGIN_DATA_ENGINE_URL"
            value = "wss://wwv-engine.vinnel.cloud/stream"
          }

          env {
            name  = "PROXY_HOST_ALLOWLIST"
            value = "*"
          }

          env {
            name = "NEXT_PUBLIC_CESIUM_ION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "cesium-ion-token"
              }
            }
          }

          env {
            name = "NEXT_PUBLIC_BING_MAPS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "bing-maps-key"
              }
            }
          }

          env {
            name = "OPENWEATHERMAP_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "openweathermap-api-key"
              }
            }
          }

          env {
            name = "ACLED_EMAIL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "acled-email"
              }
            }
          }

          env {
            name = "ACLED_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.wwv_secrets.metadata[0].name
                key  = "acled-password"
              }
            }
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1536Mi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/app/data"
          }

          startup_probe {
            http_get {
              path = "/api/health"
              port = "http"
            }
            period_seconds    = 10
            failure_threshold = 30
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.wwv_app_data.metadata[0].name
          }
        }
      }
    }
  }
}

module "wwv_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.wwv]

  name        = "wwv"
  namespace   = kubernetes_namespace_v1.worldwideview.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.wwv.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "wwv", min_memory = "512Mi", max_memory = "1536Mi" },
  ]
}

resource "kubernetes_service_v1" "wwv" {
  metadata {
    name      = "wwv"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "wwv"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "wwv_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "wwv-vinnel-cloud"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["wwv.vinnel.cloud"]
      secret_name = "wwv-vinnel-cloud-tls"
    }

    rule {
      host = "wwv.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.wwv.metadata[0].name
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

resource "kubernetes_ingress_v1" "wwv_engine_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "wwv-engine-vinnel-cloud"
    namespace = kubernetes_namespace_v1.worldwideview.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["wwv-engine.vinnel.cloud"]
      secret_name = "wwv-engine-vinnel-cloud-tls"
    }

    rule {
      host = "wwv-engine.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.wwv_data_engine.metadata[0].name
              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
}
