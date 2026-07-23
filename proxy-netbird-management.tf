locals {
  netbird_management_json = templatefile("${path.module}/netbird-management/management.json.tftpl", {
    relay_auth_secret = random_password.netbird_relay_auth_secret.result
    datastore_enc_key = random_id.netbird_datastore_enc_key.b64_std
  })
  netbird_management_config_hash = sha256(local.netbird_management_json)
}

resource "kubernetes_secret_v1" "netbird_management_config" {
  metadata {
    name      = "netbird-management-config"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  data = {
    "management.json" = local.netbird_management_json
  }
}

resource "kubernetes_persistent_volume_claim_v1" "netbird_management" {
  metadata {
    name      = "netbird-management-pvc"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
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

resource "kubernetes_deployment_v1" "netbird_management" {
  metadata {
    name      = "netbird-management"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    labels = {
      app = "netbird-management"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "netbird-management"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "netbird-management"
        }
        annotations = {
          "checksum/config" = local.netbird_management_config_hash
        }
      }

      spec {
        container {
          name  = "management"
          image = "netbirdio/management:0.74.7"
          args = [
            "--port", "80",
            "--log-file", "console",
            "--log-level", "info",
            "--disable-anonymous-metrics=true",
            "--dns-domain=nb.vinnel.cloud",
          ]

          port {
            name           = "http"
            container_port = 80
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
            mount_path = "/etc/netbird/management.json"
            sub_path   = "management.json"
            read_only  = true
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/netbird"
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
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
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.netbird_management_config.metadata[0].name
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.netbird_management.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "netbird_management_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.netbird_management]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "netbird-management"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.netbird_management.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "management", min_memory = "64Mi", max_memory = "256Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "netbird_management" {
  metadata {
    name      = "netbird-management"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "netbird-management"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}
