resource "kubernetes_namespace_v1" "kasten_io" {
  metadata {
    name = "kasten-io"
  }
}

resource "helm_release" "k10" {
  depends_on = [kubectl_manifest.snapshot_controller, kubectl_manifest.ceph_block_snapshot_class]

  name       = "k10"
  repository = "https://charts.kasten.io/"
  chart      = "k10"
  version    = "9.0.2"
  namespace  = kubernetes_namespace_v1.kasten_io.metadata[0].name

  set_sensitive = [
    {
      name  = "license"
      value = var.kasten_license_key
    }
  ]

  set = [
    {
      name  = "persistence.storageClass"
      value = "ceph-block"
    }
  ]
}

resource "kubernetes_network_policy_v1" "kasten_metrics_from_monitoring" {
  depends_on = [helm_release.k10]

  metadata {
    name      = "kasten-metrics-from-monitoring"
    namespace = kubernetes_namespace_v1.kasten_io.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "monitoring"
          }
        }
      }
      ports {
        port     = 8000
        end_port = 8999
        protocol = "TCP"
      }
    }
  }
}

resource "cloudflare_dns_record" "kasten_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "kasten.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_ingress_v1" "kasten_vinnel_cloud" {
  depends_on = [helm_release.k10]
  metadata {
    name      = "kasten-vinnel-cloud"
    namespace = kubernetes_namespace_v1.kasten_io.metadata[0].name
    annotations = merge(local.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer"       = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/app-root" = "/k10/"
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["kasten.vinnel.cloud"]
      secret_name = "kasten-vinnel-cloud-tls"
    }

    rule {
      host = "kasten.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "gateway"
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
