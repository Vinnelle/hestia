
resource "cloudflare_dns_record" "status_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "status.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_ingress_v1" "status_vinnel_cloud" {
  metadata {
    name      = "status-vinnel-cloud"
    namespace = var.namespace
    annotations = {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["status.vinnel.cloud"]
      secret_name = "status-vinnel-cloud-tls"
    }

    rule {
      host = "status.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.site_service_name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
