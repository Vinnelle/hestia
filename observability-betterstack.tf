
resource "cloudflare_dns_record" "status_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "status.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_ingress_v1" "status_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "status-vinnel-cloud"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

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
              name = module.vinnel_cloud_site.service_name
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
