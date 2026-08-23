resource "cloudflare_dns_record" "stun_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "stun.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = false
}

resource "kubernetes_deployment_v1" "netbird_stun" {
  metadata {
    name      = "netbird-stun"
    namespace = kubernetes_namespace_v1.proxy.metadata[0].name
    labels = {
      app = "netbird-stun"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "netbird-stun"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "netbird-stun"
        }
      }

      spec {
        enable_service_links = false
        host_network         = true
        dns_policy           = "ClusterFirstWithHostNet"

        container {
          name  = "coturn"
          image = "coturn/coturn:4.17.2-alpine"
          args = [
            "-n",
            "--stun-only",
            "--no-cli",
            "--no-tls",
            "--no-dtls",
            "--no-software-attribute",
            "--listening-port=3478",
          ]

          port {
            name           = "stun-udp"
            container_port = 3478
            protocol       = "UDP"
          }

          port {
            name           = "stun-tcp"
            container_port = 3478
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          readiness_probe {
            tcp_socket {
              port = "stun-tcp"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            tcp_socket {
              port = "stun-tcp"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }
      }
    }
  }
}

module "netbird_stun_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.netbird_stun]

  name        = "netbird-stun"
  namespace   = kubernetes_namespace_v1.proxy.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.netbird_stun.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "coturn", min_memory = "32Mi", max_memory = "128Mi" },
  ]
}
