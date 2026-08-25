resource "kubernetes_namespace_v1" "miniflux" {
  metadata {
    name = "miniflux"
  }
}

resource "cloudflare_dns_record" "rss_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "rss.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "miniflux_admin_password" {
  length  = 24
  special = true
}

resource "random_password" "miniflux_db_password" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "miniflux" {
  metadata {
    name      = "miniflux"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
  }
  data = {
    "admin-password" = random_password.miniflux_admin_password.result
    "db-password"    = random_password.miniflux_db_password.result
    "database-url"   = "postgres://miniflux:${random_password.miniflux_db_password.result}@miniflux-postgres.${kubernetes_namespace_v1.miniflux.metadata[0].name}.svc.cluster.local:5432/miniflux?sslmode=disable"
  }
}

resource "kubernetes_service_v1" "miniflux_postgres" {
  metadata {
    name      = "miniflux-postgres"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "miniflux-postgres"
    }
    port {
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_stateful_set_v1" "miniflux_postgres" {
  metadata {
    name      = "miniflux-postgres"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
    labels = {
      app = "miniflux-postgres"
    }
  }

  spec {
    replicas     = 1
    service_name = kubernetes_service_v1.miniflux_postgres.metadata[0].name

    selector {
      match_labels = {
        app = "miniflux-postgres"
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
    }

    template {
      metadata {
        labels = {
          app = "miniflux-postgres"
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "postgres"
          image = "postgres:18-alpine"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env {
            name  = "POSTGRES_USER"
            value = "miniflux"
          }

          env {
            name  = "POSTGRES_DB"
            value = "miniflux"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.miniflux.metadata[0].name
                key  = "db-password"
              }
            }
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "miniflux", "-d", "miniflux"]
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "miniflux", "-d", "miniflux"]
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "4Gi"
          }
        }
      }
    }
  }
}

module "miniflux_postgres_vpa" {
  source = "../../modules/vpa"

  depends_on = [kubernetes_stateful_set_v1.miniflux_postgres]

  name        = "miniflux-postgres"
  namespace   = kubernetes_namespace_v1.miniflux.metadata[0].name
  target_kind = "StatefulSet"
  target_name = kubernetes_stateful_set_v1.miniflux_postgres.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "postgres", min_memory = "128Mi", max_memory = "512Mi" },
  ]
}

resource "kubernetes_deployment_v1" "miniflux" {
  metadata {
    name      = "miniflux"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
    labels = {
      app = "miniflux"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "miniflux"
      }
    }

    template {
      metadata {
        labels = {
          app = "miniflux"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "miniflux"
          image = "miniflux/miniflux:2.3.3"

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name  = "LISTEN_ADDR"
            value = "0.0.0.0:8080"
          }

          env {
            name  = "BASE_URL"
            value = "https://rss.vinnel.cloud"
          }

          env {
            name  = "RUN_MIGRATIONS"
            value = "1"
          }

          env {
            name  = "CREATE_ADMIN"
            value = "1"
          }

          env {
            name  = "ADMIN_USERNAME"
            value = "admin"
          }

          env {
            name  = "METRICS_COLLECTOR"
            value = "1"
          }

          env {
            name  = "METRICS_ALLOWED_NETWORKS"
            value = "10.0.0.0/8"
          }

          env {
            name = "ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.miniflux.metadata[0].name
                key  = "admin-password"
              }
            }
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.miniflux.metadata[0].name
                key  = "database-url"
              }
            }
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "1"
              memory = "256Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/healthcheck"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            http_get {
              path = "/healthcheck"
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

module "miniflux_vpa" {
  source = "../../modules/vpa"

  depends_on = [kubernetes_deployment_v1.miniflux]

  name        = "miniflux"
  namespace   = kubernetes_namespace_v1.miniflux.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.miniflux.metadata[0].name
  update_mode = "Auto"
  container_policies = [
    { container_name = "miniflux", min_memory = "64Mi", max_memory = "256Mi" },
  ]
}

resource "kubernetes_service_v1" "miniflux" {
  metadata {
    name      = "miniflux"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "miniflux"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "rss_vinnel_cloud" {
  metadata {
    name      = "rss-vinnel-cloud"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["rss.vinnel.cloud"]
      secret_name = "rss-vinnel-cloud-tls"
    }

    rule {
      host = "rss.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.miniflux.metadata[0].name
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
