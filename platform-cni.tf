resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.19.6"
  namespace  = "kube-system"

  values = [
    file("${path.module}/helm-values/cilium/values.yaml"),
    yamlencode({
      podAnnotations = {
        "config-hash" = sha256(file("${path.module}/helm-values/cilium/values.yaml"))
      }
    })
  ]
}

resource "cloudflare_dns_record" "hubble_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "hubble.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_ingress_v1" "hubble_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx, helm_release.cilium]
  metadata {
    name      = "hubble-vinnel-cloud"
    namespace = "kube-system"
    annotations = merge(local.admin_framed_service_annotations["hubble"], {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["hubble.vinnel.cloud"]
      secret_name = "hubble-vinnel-cloud-tls"
    }

    rule {
      host = "hubble.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "hubble-ui"
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
