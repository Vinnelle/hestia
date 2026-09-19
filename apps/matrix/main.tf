resource "kubernetes_namespace_v1" "matrix" {
  metadata {
    name = "matrix"
  }
}

resource "cloudflare_dns_record" "matrix_vinnel_cloud" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "matrix_db_password" {
  length  = 32
  special = false
}

resource "random_password" "matrix_registration_shared_secret" {
  length  = 64
  special = false
}

resource "random_password" "matrix_macaroon_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "matrix_form_secret" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "matrix" {
  metadata {
    name      = "matrix"
    namespace = kubernetes_namespace_v1.matrix.metadata[0].name
  }
  data = {
    "db-password" = random_password.matrix_db_password.result
    "homeserver.yaml" = templatefile("${path.module}/homeserver.yaml.tftpl", {
      server_name                = var.server_name
      hostname                   = var.hostname
      db_password                = random_password.matrix_db_password.result
      registration_shared_secret = random_password.matrix_registration_shared_secret.result
      macaroon_secret_key        = random_password.matrix_macaroon_secret_key.result
      form_secret                = random_password.matrix_form_secret.result
    })
  }
}

resource "kubernetes_service_v1" "matrix_postgres" {
  metadata {
    name      = "matrix-postgres"
    namespace = kubernetes_namespace_v1.matrix.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "matrix-postgres"
    }
    port {
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_stateful_set_v1" "matrix_postgres" {
  metadata {
    name      = "matrix-postgres"
    namespace = kubernetes_namespace_v1.matrix.metadata[0].name
    labels = {
      app = "matrix-postgres"
    }
  }

  spec {
    replicas     = 1
    service_name = kubernetes_service_v1.matrix_postgres.metadata[0].name

    selector {
      match_labels = {
        app = "matrix-postgres"
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
    }

    template {
      metadata {
        labels = {
          app = "matrix-postgres"
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
            value = "synapse"
          }

          env {
            name  = "POSTGRES_DB"
            value = "synapse"
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.matrix.metadata[0].name
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
              command = ["pg_isready", "-U", "synapse", "-d", "synapse"]
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "synapse", "-d", "synapse"]
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
            storage = "8Gi"
          }
        }
      }
    }
  }
}

module "matrix_postgres_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_stateful_set_v1.matrix_postgres]

  name        = "matrix-postgres"
  namespace   = kubernetes_namespace_v1.matrix.metadata[0].name
  target_kind = "StatefulSet"
  target_name = kubernetes_stateful_set_v1.matrix_postgres.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "postgres", min_memory = "128Mi", max_memory = "512Mi" },
  ]
}

resource "kubernetes_service_v1" "matrix_synapse" {
  metadata {
    name      = "matrix-synapse"
    namespace = kubernetes_namespace_v1.matrix.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "matrix-synapse"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_stateful_set_v1" "matrix_synapse" {
  metadata {
    name      = "matrix-synapse"
    namespace = kubernetes_namespace_v1.matrix.metadata[0].name
    labels = {
      app = "matrix-synapse"
    }
  }

  spec {
    replicas     = 1
    service_name = kubernetes_service_v1.matrix_synapse.metadata[0].name

    selector {
      match_labels = {
        app = "matrix-synapse"
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
    }

    template {
      metadata {
        labels = {
          app = "matrix-synapse"
        }
      }

      spec {
        enable_service_links = false

        security_context {
          run_as_user  = "991"
          run_as_group = "991"
          fs_group     = "991"
        }

        init_container {
          name    = "generate-keys"
          image   = "matrixdotorg/synapse:v1.161.0"
          command = ["python", "-m", "synapse.app.homeserver", "--config-path", "/config/homeserver.yaml", "--generate-keys"]

          volume_mount {
            name       = "config"
            mount_path = "/config"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        container {
          name    = "synapse"
          image   = "matrixdotorg/synapse:v1.161.0"
          command = ["python", "-m", "synapse.app.homeserver", "--config-path", "/config/homeserver.yaml"]

          port {
            name           = "http"
            container_port = 8008
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "2"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
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
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 5
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.matrix.metadata[0].name
            items {
              key  = "homeserver.yaml"
              path = "homeserver.yaml"
            }
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
            storage = "10Gi"
          }
        }
      }
    }
  }
}

module "matrix_synapse_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_stateful_set_v1.matrix_synapse]

  name        = "matrix-synapse"
  namespace   = kubernetes_namespace_v1.matrix.metadata[0].name
  target_kind = "StatefulSet"
  target_name = kubernetes_stateful_set_v1.matrix_synapse.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "synapse", min_memory = "256Mi", max_memory = "1Gi" },
  ]
}

resource "kubernetes_ingress_v1" "matrix_vinnel_cloud" {
  metadata {
    name      = "matrix-vinnel-cloud"
    namespace = kubernetes_namespace_v1.matrix.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = var.cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "50m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "120"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.hostname]
      secret_name = "matrix-vinnel-cloud-tls"
    }

    rule {
      host = var.hostname
      http {
        path {
          path      = "/_matrix"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.matrix_synapse.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path      = "/_synapse/client"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.matrix_synapse.metadata[0].name
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

resource "kubernetes_ingress_v1" "matrix_vinnel_cloud_root" {
  metadata {
    name      = "matrix-vinnel-cloud-root"
    namespace = kubernetes_namespace_v1.matrix.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/temporal-redirect" = "https://${var.server_name}"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.hostname]
      secret_name = "matrix-vinnel-cloud-tls"
    }

    rule {
      host = var.hostname
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.matrix_synapse.metadata[0].name
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
