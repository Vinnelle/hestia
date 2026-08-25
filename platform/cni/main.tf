resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.20.1"
  namespace  = "kube-system"

  values = [
    file("${path.module}/../helm-values/cilium/values.yaml"),
    yamlencode({
      podAnnotations = {
        "config-hash" = sha256(file("${path.module}/../helm-values/cilium/values.yaml"))
      }
    })
  ]
}

resource "cloudflare_dns_record" "hubble_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "hubble.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_ingress_v1" "hubble_vinnel_cloud" {
  depends_on = [helm_release.cilium]
  metadata {
    name      = "hubble-vinnel-cloud"
    namespace = "kube-system"
    annotations = merge(var.admin_frame_service_annotations, {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

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
