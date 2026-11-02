resource "kubernetes_namespace_v1" "vinnel_cloud" {
  metadata {
    name = "vinnel-cloud"
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig_vinnel_cloud" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

module "vinnel_cloud_site" {
  source = "../static-site"

  depends_on = [
    kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud,
  ]

  site_slug = "vinnel-cloud"
  domain    = "vinnel.cloud"
  zone_id   = var.zone_id
  relay_ip  = var.relay_ip

  cluster_issuer = var.cluster_issuer

  namespace            = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  registry_secret_name = kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud.metadata[0].name
  image                = var.images["vinnel-cloud-site"]
  replicas             = 2

  cpu_request    = "250m"
  memory_request = "64Mi"
  cpu_limit      = "500m"
  memory_limit   = "256Mi"

  vpa_update_mode = "Auto"
}

resource "cloudflare_dns_record" "pve" {
  zone_id = var.zone_id
  name    = "pve.vinnel.cloud"
  type    = "A"
  content = var.relay_ip
  ttl     = 60
  proxied = false
}

resource "kubernetes_ingress_v1" "pve_redirect" {
  metadata {
    name      = "pve-redirect"
    namespace = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                = var.cluster_issuer
      "nginx.ingress.kubernetes.io/temporal-redirect" = "https://vinnel.cloud"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["pve.vinnel.cloud"]
      secret_name = "pve-vinnel-cloud-tls"
    }

    rule {
      host = "pve.vinnel.cloud"
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
