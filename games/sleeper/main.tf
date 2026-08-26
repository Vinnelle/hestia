resource "kubernetes_secret_v1" "registry_dockerconfig" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = var.namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

resource "kubernetes_secret_v1" "satisfactory_admin" {
  metadata {
    name      = "satisfactory-admin"
    namespace = var.namespace
  }

  data = {
    ADMIN_PASSWORD = var.satisfactory_admin_password
  }
}

resource "kubernetes_service_account_v1" "game_sleeper" {
  metadata {
    name      = "game-sleeper"
    namespace = var.namespace
  }
}

resource "kubernetes_role_v1" "game_sleeper" {
  metadata {
    name      = "game-sleeper"
    namespace = var.namespace
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments/scale"]
    verbs      = ["get", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "game_sleeper" {
  metadata {
    name      = "game-sleeper"
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.game_sleeper.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.game_sleeper.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_deployment_v1" "game_sleeper" {
  metadata {
    name      = "game-sleeper"
    namespace = var.namespace
    labels = {
      app = "game-sleeper"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "game-sleeper"
      }
    }

    template {
      metadata {
        labels = {
          app = "game-sleeper"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.game_sleeper.metadata[0].name
        enable_service_links = false
        host_network         = true
        dns_policy           = "ClusterFirstWithHostNet"

        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig.metadata[0].name
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 10001
        }

        container {
          name  = "sleeper"
          image = var.image

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = var.minecraft_port
            protocol       = "TCP"
          }

          env {
            name  = "ROLE"
            value = "game-sleeper"
          }

          env {
            name  = "OTEL_COLLECTOR_ENDPOINT"
            value = "signoz-otel-collector.${var.observability_namespace}.svc.cluster.local:4317"
          }

          env {
            name  = "MINECRAFT_HOST"
            value = var.node_ip
          }

          env {
            name  = "MINECRAFT_PORT"
            value = tostring(var.minecraft_port)
          }

          env {
            name  = "MINECRAFT_SLEEPER_ADDR"
            value = ":${var.minecraft_port}"
          }

          env {
            name  = "SATISFACTORY_HOST"
            value = var.node_ip
          }

          env {
            name = "SATISFACTORY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.satisfactory_admin.metadata[0].name
                key  = "ADMIN_PASSWORD"
              }
            }
          }

          env {
            name  = "GAME_IDLE_TIMEOUT"
            value = var.idle_timeout
          }

          env {
            name  = "GAME_SLEEP_POLL"
            value = var.poll_interval
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }
}
