
# status.vinnel.cloud fronts the Better Stack status page (vinnel.betteruptime.com)
# from our own origin instead of CNAME-ing at theirs: a proxied CNAME to
# betteruptime never resolved (Better Stack only answers for hostnames registered
# on their side), so the record pointed at a host that did not exist. The page is
# hestia/vinnel-cloud/site/html/status.html, served by the existing site
# deployment — conf/nginx.conf rewrites `/` to it for this host only, so no second
# image, deployment or build target exists just to hold one iframe.
resource "cloudflare_dns_record" "status_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "status.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

# Its own Ingress and TLS secret rather than another host on the site's Ingress:
# adding a SAN to vinnel-cloud-tls would make cert-manager reissue the apex
# certificate, and the apex is the one cert worth not churning.
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
              name = kubernetes_service_v1.vinnel_cloud_site.metadata[0].name
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
