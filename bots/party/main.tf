locals {
  knowledge = file("${path.module}/knowledge.md")
}

resource "kubernetes_namespace_v1" "party" {
  metadata {
    name = "party"
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.party.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

resource "random_password" "chat_identity" {
  length  = 48
  special = false
}

resource "random_id" "machine_id" {
  byte_length = 16
}

resource "kubernetes_secret_v1" "party" {
  metadata {
    name      = "party"
    namespace = kubernetes_namespace_v1.party.metadata[0].name
  }

  data = {
    LLM_API_KEY        = var.llm_api_key
    CHAT_SIGN_PASSWORD = random_password.chat_identity.result
    "machine-id"       = "${random_id.machine_id.hex}\n"
  }
}

resource "kubernetes_config_map_v1" "knowledge" {
  metadata {
    name      = "knowledge"
    namespace = kubernetes_namespace_v1.party.metadata[0].name
  }

  data = {
    "knowledge.md" = local.knowledge
  }
}

resource "kubernetes_deployment_v1" "party" {
  metadata {
    name      = "party"
    namespace = kubernetes_namespace_v1.party.metadata[0].name
    labels = {
      app = "party"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "party"
      }
    }

    template {
      metadata {
        labels = {
          app = "party"
        }
        annotations = {
          "checksum/knowledge" = sha256(local.knowledge)
        }
      }

      spec {
        enable_service_links             = false
        automount_service_account_token  = false
        termination_grace_period_seconds = 30

        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig.metadata[0].name
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "party"
          image = var.image

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          env {
            name  = "CHAT_SESSION"
            value = var.session
          }

          env {
            name  = "CHAT_NICK"
            value = var.nick
          }

          env {
            name  = "CHAT_COLOUR"
            value = var.colour
          }

          env {
            name = "CHAT_SIGN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.party.metadata[0].name
                key  = "CHAT_SIGN_PASSWORD"
              }
            }
          }

          env {
            name  = "LLM_BASE_URL"
            value = var.llm_base_url
          }

          env {
            name  = "LLM_MODEL"
            value = var.llm_model
          }

          env {
            name = "LLM_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.party.metadata[0].name
                key  = "LLM_API_KEY"
              }
            }
          }

          env {
            name  = "KNOWLEDGE_FILE"
            value = "/etc/party/knowledge.md"
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "home"
            mount_path = "/home/party"
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          volume_mount {
            name       = "tor"
            mount_path = "/var/lib/tor"
          }

          volume_mount {
            name       = "knowledge"
            mount_path = "/etc/party"
            read_only  = true
          }

          volume_mount {
            name       = "machine-id"
            mount_path = "/etc/machine-id"
            sub_path   = "machine-id"
            read_only  = true
          }
        }

        volume {
          name = "home"
          empty_dir {
            size_limit = "64Mi"
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "64Mi"
          }
        }

        volume {
          name = "tor"
          empty_dir {
            size_limit = "256Mi"
          }
        }

        volume {
          name = "knowledge"
          config_map {
            name = kubernetes_config_map_v1.knowledge.metadata[0].name
          }
        }

        volume {
          name = "machine-id"
          secret {
            secret_name = kubernetes_secret_v1.party.metadata[0].name
            items {
              key  = "machine-id"
              path = "machine-id"
            }
          }
        }
      }
    }
  }
}
