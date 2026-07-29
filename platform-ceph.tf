resource "kubernetes_namespace_v1" "rook_ceph" {
  metadata {
    name = "rook-ceph"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "rook_ceph_operator" {
  name       = "rook-ceph"
  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph"
  version    = "v1.20.3"
  namespace  = kubernetes_namespace_v1.rook_ceph.metadata[0].name
}

resource "helm_release" "rook_ceph_cluster" {
  name       = "rook-ceph-cluster"
  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph-cluster"
  version    = "v1.20.3"
  namespace  = kubernetes_namespace_v1.rook_ceph.metadata[0].name

  values = [
    file("${path.module}/helm-values/rook-ceph-cluster/values.yaml")
  ]

  depends_on = [helm_release.rook_ceph_operator]
}

resource "helm_release" "ceph_csi_drivers" {
  name       = "ceph-csi-drivers"
  repository = "https://ceph.github.io/ceph-csi-operator"
  chart      = "ceph-csi-drivers"
  version    = "1.0.4"
  namespace  = kubernetes_namespace_v1.rook_ceph.metadata[0].name

  values = [
    file("${path.module}/helm-values/ceph-csi-drivers/values.yaml")
  ]

  depends_on = [helm_release.rook_ceph_cluster]
}

data "kubernetes_secret_v1" "rook_ceph_dashboard_password" {
  depends_on = [helm_release.rook_ceph_cluster]
  metadata {
    name      = "rook-ceph-dashboard-password"
    namespace = kubernetes_namespace_v1.rook_ceph.metadata[0].name
  }
}

resource "cloudflare_dns_record" "ceph_dashboard_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "ceph.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_ingress_v1" "ceph_dashboard_vinnel_cloud" {
  # ingress_nginx must land first: the configuration-snippet below is rejected by
  # the validating webhook until the controller has picked up
  # allow-snippet-annotations from its ConfigMap.
  depends_on = [helm_release.rook_ceph_cluster, helm_release.ingress_nginx]
  metadata {
    name      = "ceph-dashboard-vinnel-cloud"
    namespace = kubernetes_namespace_v1.rook_ceph.metadata[0].name
    annotations = merge(local.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer

      # local.admin_framed_annotations plus a CSP replacement. The Ceph dashboard
      # sends exactly "frame-ancestors 'self';" and nothing else (checked
      # 2026-07-29), so replacing the whole header costs no script-src/style-src
      # protection — the usual reason the shared local leaves CSP alone does not
      # apply here. Re-check this after a Rook upgrade.
      "nginx.ingress.kubernetes.io/configuration-snippet" = <<-EOT
        more_clear_headers "X-Frame-Options";
        more_set_headers "Content-Security-Policy: frame-ancestors https://admin.vinnel.cloud";
        if ($http_sec_fetch_dest = "document") {
          return 302 https://vinnel.cloud/;
        }
      EOT
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["ceph.vinnel.cloud"]
      secret_name = "ceph-vinnel-cloud-tls"
    }

    rule {
      host = "ceph.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "rook-ceph-mgr-dashboard"
              port {
                number = 7000
              }
            }
          }
        }
      }
    }
  }
}
