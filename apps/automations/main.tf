locals {
  enabled      = var.llm_base_url != ""
  port         = 8080
  accept_label = "review-accepted"
}

resource "kubernetes_namespace_v1" "automations" {
  metadata {
    name = "automations"
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.automations.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

resource "gitlab_project_access_token" "automations" {
  count = local.enabled ? 1 : 0

  project      = var.gitlab_project_id
  name         = "automations"
  scopes       = ["api"]
  access_level = "reporter"
  expires_at   = "2027-08-01"
}

resource "kubernetes_secret_v1" "automations" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "automations"
    namespace = kubernetes_namespace_v1.automations.metadata[0].name
  }

  data = {
    GITLAB_TOKEN = gitlab_project_access_token.automations[0].token
    LLM_API_KEY  = var.llm_api_key
  }
}

resource "gitlab_project_label" "review_accepted" {
  count = local.enabled ? 1 : 0

  project     = var.gitlab_project_id
  name        = local.accept_label
  color       = "#d9534f"
  description = "Lets a Renovate update through after the reviewer called it breaking: add the label, then retry the renovate_review job"
}

resource "kubernetes_deployment_v1" "automations" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "automations"
    namespace = kubernetes_namespace_v1.automations.metadata[0].name
    labels = {
      app = "automations"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "automations"
      }
    }

    template {
      metadata {
        labels = {
          app = "automations"
        }
      }

      spec {
        enable_service_links            = false
        automount_service_account_token = false

        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig[0].metadata[0].name
        }

        host_aliases {
          ip        = var.node_ip
          hostnames = ["gitlab.vinnel.cloud"]
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
          name  = "automations"
          image = var.image

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "http"
            container_port = local.port
          }

          env {
            name  = "GITLAB_API_URL"
            value = "https://gitlab.vinnel.cloud/api/v4"
          }

          env {
            name  = "GITLAB_PROJECT_ID"
            value = var.gitlab_project_id
          }

          env {
            name = "GITLAB_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.automations[0].metadata[0].name
                key  = "GITLAB_TOKEN"
              }
            }
          }

          env {
            name  = "RENOVATE_AUTHOR_ID"
            value = tostring(var.renovate_author_id)
          }

          env {
            name  = "REVIEW_ACCEPT_LABEL"
            value = gitlab_project_label.review_accepted[0].name
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
                name = kubernetes_secret_v1.automations[0].metadata[0].name
                key  = "LLM_API_KEY"
              }
            }
          }

          env {
            name  = "OTEL_COLLECTOR_ENDPOINT"
            value = "otel-collector.${var.observability_namespace}.svc.cluster.local:4317"
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "128Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds = 10
          }

          liveness_probe {
            http_get {
              path = "/healthz"
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

resource "kubernetes_service_v1" "automations" {
  count = local.enabled ? 1 : 0

  metadata {
    name      = "automations"
    namespace = kubernetes_namespace_v1.automations.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "automations"
    }
    port {
      name        = "http"
      port        = local.port
      target_port = "http"
    }
  }
}

resource "gitlab_project_variable" "renovate_review_url" {
  count = local.enabled ? 1 : 0

  depends_on = [kubernetes_deployment_v1.automations]

  project   = var.gitlab_project_id
  key       = "RENOVATE_REVIEW_URL"
  value     = "http://${kubernetes_service_v1.automations[0].metadata[0].name}.${kubernetes_namespace_v1.automations.metadata[0].name}.svc.cluster.local:${local.port}/renovate/reviews"
  masked    = false
  protected = false
}
