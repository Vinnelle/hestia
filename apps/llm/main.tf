locals {
  model = jsondecode(file("${path.module}/model.json"))
  port  = 8080
}

resource "kubernetes_namespace_v1" "llm" {
  metadata {
    name = "llm"
  }
}

resource "random_password" "api_key" {
  length  = 48
  special = false
}

resource "kubernetes_secret_v1" "llm" {
  metadata {
    name      = "llm"
    namespace = kubernetes_namespace_v1.llm.metadata[0].name
  }

  data = {
    "api-keys" = random_password.api_key.result
  }
}

resource "kubernetes_persistent_volume_claim_v1" "models" {
  metadata {
    name      = "models"
    namespace = kubernetes_namespace_v1.llm.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path-bulk"
    resources {
      requests = {
        storage = "30Gi"
      }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_deployment_v1" "llm" {
  wait_for_rollout = false

  metadata {
    name      = "llm"
    namespace = kubernetes_namespace_v1.llm.metadata[0].name
    labels = {
      app = "llm"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "llm"
      }
    }

    template {
      metadata {
        labels = {
          app = "llm"
        }
      }

      spec {
        runtime_class_name              = var.runtime_class_name
        enable_service_links            = false
        automount_service_account_token = false

        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        init_container {
          name    = "fetch-model"
          image   = "docker.io/library/alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a"
          command = ["sh", "-c", file("${path.module}/fetch-model.sh")]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          env {
            name  = "MODEL_FILE"
            value = local.model.file
          }

          env {
            name  = "MODEL_URL"
            value = local.model.url
          }

          env {
            name  = "MODEL_SHA256"
            value = local.model.sha256
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "1"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "models"
            mount_path = "/models"
          }
        }

        container {
          name  = "llama-server"
          image = "ghcr.io/ggml-org/llama.cpp:server-cuda-b11804@sha256:490d8cd8000203a3ab8fdfce14ef931e2aa85affd4dd4447bcc75f299f00fd9a"
          args = [
            "--model", "/models/${local.model.file}",
            "--alias", local.model.alias,
            "--ctx-size", tostring(local.model.context),
            "--parallel", "1",
            "--host", "0.0.0.0",
            "--port", tostring(local.port),
            "--api-key-file", "/run/secrets/llm/api-keys",
            "--no-webui",
            "--metrics",
          ]

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
            name  = "HOME"
            value = "/tmp"
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu              = "4"
              memory           = "4Gi"
              "nvidia.com/gpu" = "1"
            }
          }

          volume_mount {
            name       = "models"
            mount_path = "/models"
            read_only  = true
          }

          volume_mount {
            name       = "api-key"
            mount_path = "/run/secrets/llm"
            read_only  = true
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          startup_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds    = 10
            failure_threshold = 60
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds = 10
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds    = 30
            timeout_seconds   = 10
            failure_threshold = 3
          }
        }

        volume {
          name = "models"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.models.metadata[0].name
          }
        }

        volume {
          name = "api-key"
          secret {
            secret_name  = kubernetes_secret_v1.llm.metadata[0].name
            default_mode = "0440"
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "llm" {
  metadata {
    name      = "llm"
    namespace = kubernetes_namespace_v1.llm.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "llm"
    }
    port {
      name        = "http"
      port        = local.port
      target_port = "http"
    }
  }
}

resource "kubectl_manifest" "scrape" {
  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMPodScrape"
    metadata = {
      name      = "llm"
      namespace = kubernetes_namespace_v1.llm.metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = {
          app = "llm"
        }
      }
      podMetricsEndpoints = [{
        port = "http"
        path = "/metrics"
        bearerTokenSecret = {
          name = kubernetes_secret_v1.llm.metadata[0].name
          key  = "api-keys"
        }
      }]
    }
  })
}
