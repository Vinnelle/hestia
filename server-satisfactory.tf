resource "cloudflare_dns_record" "factory_vin_moe" {
  zone_id = data.cloudflare_zone.vin_moe.id
  name    = "factory.vin.moe"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = false
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
            container_port = 8888
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
              port = 7777
            }
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 6
          }

          liveness_probe {
            tcp_socket {
              port = 7777
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            failure_threshold     = 6
          }
        }

        volume {
          name = "saves"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.satisfactory_saves.metadata[0].name
          }
        }
      }
    }
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
