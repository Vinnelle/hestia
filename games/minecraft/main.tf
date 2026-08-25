resource "kubernetes_namespace_v1" "games" {
  metadata {
    name = "games"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "cloudflare_dns_record" "mc_vin_moe" {
  zone_id = var.zone_id
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
    namespace = kubernetes_namespace_v1.games.metadata[0].name
  }

  data = {
    CF_API_KEY    = var.curseforge_api_key
    RCON_PASSWORD = random_password.minecraft_rcon.result
  }
}

resource "kubernetes_secret_v1" "minecraft_rcon_admin" {
  metadata {
    name      = "minecraft-rcon"
    namespace = var.dashboard_namespace
  }

  data = {
    RCON_PASSWORD = random_password.minecraft_rcon.result
  }
}

locals {
  minecraft_modpack_zip = "/data/.downloads/modpacks/create-ultimate-selection-2-11.1.0.zip"

  minecraft_config_hash = sha256(join("", [
    var.curseforge_api_key,
    var.minecraft_modpack_zip_url,
    local.minecraft_modpack_zip,
    random_password.minecraft_rcon.result,
  ]))
}

resource "kubernetes_persistent_volume_claim_v1" "minecraft_data" {
  metadata {
    name      = "minecraft-data-pvc"
    namespace = kubernetes_namespace_v1.games.metadata[0].name
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
    namespace = kubernetes_namespace_v1.games.metadata[0].name
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
        annotations = {
          "config-hash" = local.minecraft_config_hash
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

        init_container {
          name  = "fetch-modpack"
          image = "curlimages/curl:8.21.0@sha256:7c12af72ceb38b7432ab85e1a265cff6ae58e06f95539d539b654f2cfa64bb13"

          command = ["/bin/sh", "-c", <<-EOT
            set -eu
            if [ -s "${local.minecraft_modpack_zip}" ]; then exit 0; fi
            mkdir -p "$(dirname "${local.minecraft_modpack_zip}")"
            curl -fsSL --retry 3 -o "${local.minecraft_modpack_zip}.part" "$MODPACK_ZIP_URL"
            head -c 2 "${local.minecraft_modpack_zip}.part" | grep -q PK || { rm -f "${local.minecraft_modpack_zip}.part"; exit 1; }
            mv "${local.minecraft_modpack_zip}.part" "${local.minecraft_modpack_zip}"
            EOT
          ]

          env {
            name  = "MODPACK_ZIP_URL"
            value = var.minecraft_modpack_zip_url
          }

          security_context {
            run_as_user                = 1000
            run_as_group               = 1000
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
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
        }

        container {
          name  = "minecraft"
          image = "itzg/minecraft-server:java21@sha256:3527decf11fbdeb77acd1b035ad65dd1fc83a288c2891a68b31e98b7330a610f"

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
            name  = "CF_MODPACK_ZIP"
            value = local.minecraft_modpack_zip
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
            value = "WakaWakaWakaWakaWakaWakaWakaWaka"
          }

          env {
            name  = "SERVER_NAME"
            value = "Chiken NUget"
          }

          env {
            name  = "ALLOW_FLIGHT"
            value = "true"
          }

          env {
            name  = "TZ"
            value = "Europe/London"
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

  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

module "minecraft_vpa" {
  source = "../../modules/vpa"


  name        = "minecraft"
  namespace   = kubernetes_namespace_v1.games.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.minecraft.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "minecraft", min_memory = "18Gi", max_memory = "18Gi" },
  ]
}
