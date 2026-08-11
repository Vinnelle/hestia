resource "cloudflare_dns_record" "factory_vin_moe" {
  zone_id = data.cloudflare_zone.vin_moe.id
  name    = "factory.vin.moe"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = false
}

resource "kubernetes_secret_v1" "satisfactory_admin" {
  metadata {
    name      = "satisfactory-admin"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  data = {
    ADMIN_PASSWORD = var.satisfactory_admin_password
  }
}

resource "kubernetes_persistent_volume_claim_v1" "satisfactory_saves" {
  metadata {
    name      = "satisfactory-saves-pvc"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_config_map_v1" "satisfactory_saves_http_conf" {
  metadata {
    name      = "satisfactory-saves-http-conf"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }

  data = {
    "default.conf" = <<-EOT
    server {
      listen 8080;
      location / {
        root /config/saved/server;
        autoindex on;
        autoindex_format json;
      }
    }
    EOT
  }
}

resource "kubernetes_service_v1" "satisfactory_saves" {
  metadata {
    name      = "satisfactory-saves"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }

  spec {
    selector = {
      app = "satisfactory"
    }
    port {
      port        = 8080
      target_port = "saves-http"
    }
  }
}

resource "kubernetes_deployment_v1" "satisfactory" {
  metadata {
    name      = "satisfactory"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
    labels = {
      app = "satisfactory"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "satisfactory"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "satisfactory"
        }
      }

      spec {
        enable_service_links = false
        host_network         = true
        dns_policy           = "ClusterFirstWithHostNet"

        security_context {
          fs_group = 1000
        }

        container {
          name  = "satisfactory"
          image = "wolveix/satisfactory-server:v1.9.10"

          env {
            name  = "SERVERMESSAGINGPORT"
            value = "8889"
          }

          port {
            name           = "game-tcp"
            container_port = 7777
            protocol       = "TCP"
          }

          port {
            name           = "game-udp"
            container_port = 7777
            protocol       = "UDP"
          }

          port {
            name           = "messaging"
            container_port = 8889
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "4000m"
              memory = "16Gi"
            }
            limits = {
              cpu    = "8000m"
              memory = "28Gi"
            }
          }

          volume_mount {
            name       = "saves"
            mount_path = "/config"
          }

          readiness_probe {
            tcp_socket {
              port = "messaging"
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 6
          }

          liveness_probe {
            tcp_socket {
              port = "messaging"
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            failure_threshold     = 6
          }
        }

        container {
          name  = "saves-http"
          image = "nginxinc/nginx-unprivileged:1.31-alpine@sha256:59ccf0943b0b8e8d9e6ea9039a39555730f544701a655c596f7df7d096c593f5"

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "saves-http"
            container_port = 8080
          }

          volume_mount {
            name       = "saves"
            mount_path = "/config"
            read_only  = true
          }

          volume_mount {
            name       = "saves-http-conf"
            mount_path = "/etc/nginx/conf.d/default.conf"
            sub_path   = "default.conf"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          readiness_probe {
            tcp_socket {
              port = 8080
            }
            period_seconds = 10
          }
        }

        volume {
          name = "saves"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.satisfactory_saves.metadata[0].name
          }
        }

        volume {
          name = "saves-http-conf"
          config_map {
            name = kubernetes_config_map_v1.satisfactory_saves_http_conf.metadata[0].name
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

resource "kubectl_manifest" "satisfactory_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.satisfactory]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "satisfactory"
    namespace   = kubernetes_namespace_v1.server.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.satisfactory.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "satisfactory", min_memory = "16Gi", max_memory = "28Gi" },
    ]
  })
}
