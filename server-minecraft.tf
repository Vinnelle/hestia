resource "cloudflare_dns_record" "mc_vin_moe" {
  zone_id = data.cloudflare_zone.vin_moe.id
  name    = "mc.vin.moe"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = false
}

resource "random_password" "minecraft_rcon" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "minecraft" {
  metadata {
    name      = "minecraft-secrets"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }

  data = {
    CF_API_KEY    = var.curseforge_api_key
    RCON_PASSWORD = random_password.minecraft_rcon.result
  }
}

resource "kubernetes_persistent_volume_claim_v1" "minecraft_data" {
  metadata {
    name      = "minecraft-data-pvc"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "64Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "minecraft" {
  metadata {
    name      = "minecraft"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
    labels = {
      app = "minecraft"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "minecraft"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "minecraft"
        }
      }

      spec {
        enable_service_links             = false
        host_network                     = true
        dns_policy                       = "ClusterFirstWithHostNet"
        termination_grace_period_seconds = 120

        security_context {
          fs_group = 1000
        }

        container {
          name  = "minecraft"
          image = "itzg/minecraft-server:java21@sha256:6f2db1af7f424006b8a5b2b9bec4224bd682eb81213f39b28ba731d81aa63e49"

          env {
            name  = "EULA"
            value = "TRUE"
          }

          env {
            name  = "TYPE"
            value = "AUTO_CURSEFORGE"
          }

          env {
            name  = "CF_SLUG"
            value = "create-ultimate-selection-2"
          }

          env {
            name  = "CF_FILENAME_MATCHER"
            value = "11.1.0"
          }

          env {
            name  = "CF_DOWNLOADS_REPO"
            value = "/data/.downloads"
          }

          env {
            name  = "MEMORY"
            value = "16G"
          }

          env {
            name  = "USE_AIKAR_FLAGS"
            value = "true"
          }

          env {
            name  = "MAX_TICK_TIME"
            value = "-1"
          }

          env {
            name  = "ENABLE_ROLLING_LOGS"
            value = "true"
          }

          env {
            name  = "MOTD"
            value = "Create: Ultimate Selection 2"
          }

          env {
            name  = "TZ"
            value = "Europe/Amsterdam"
          }

          env {
            name  = "STOP_SERVER_ANNOUNCE_DELAY"
            value = "10"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.minecraft.metadata[0].name
            }
          }

          port {
            name           = "game"
            container_port = 25565
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "6000m"
              memory = "18Gi"
            }
            limits = {
              cpu    = "12000m"
              memory = "20Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          startup_probe {
            exec {
              command = ["mc-health"]
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            failure_threshold     = 80
          }

          readiness_probe {
            exec {
              command = ["mc-health"]
            }
            period_seconds    = 30
            failure_threshold = 4
          }

          liveness_probe {
            exec {
              command = ["mc-health"]
            }
            period_seconds    = 60
            failure_threshold = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.minecraft_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "minecraft_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.minecraft]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "minecraft"
    namespace   = kubernetes_namespace_v1.server.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.minecraft.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "minecraft", min_memory = "18Gi", max_memory = "20Gi" },
    ]
  })
}
