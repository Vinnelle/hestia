
resource "cloudflare_dns_record" "grafana_admin_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "grafana.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_persistent_volume_claim_v1" "grafana" {
  metadata {
    name      = "grafana-pvc"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    labels = {
      app = "grafana"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        security_context {
          fs_group    = 472
          run_as_user = 472
        }

        container {
          name  = "grafana"
          image = "grafana/grafana:13.1.0"

          port {
            container_port = 3000
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "grafana-storage"
            mount_path = "/var/lib/grafana"
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = "3000"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = "3000"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "grafana-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.grafana.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "grafana_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.grafana]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "grafana"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.grafana.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "grafana", min_memory = "256Mi", max_memory = "1Gi" },
    ]
  })
}

resource "kubernetes_service_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "grafana"
    }
    port {
      port        = 80
      target_port = "3000"
    }
  }
}

resource "kubernetes_ingress_v1" "grafana_admin_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "grafana-admin-vinnel-cloud"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["grafana.vinnel.cloud"]
      secret_name = "grafana-vinnel-cloud-tls"
    }

    rule {
      host = "grafana.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.grafana.metadata[0].name
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

resource "grafana_dashboard" "kubernetes_cluster" {
  folder = grafana_folder.infrastructure.uid
  config_json = templatefile("${path.module}/grafana-dashboards/kubernetes-cluster.json.tftpl", {
    prometheus_ds = local.prometheus_ds
  })
}

resource "grafana_dashboard" "vps" {
  folder = grafana_folder.infrastructure.uid
  config_json = templatefile("${path.module}/grafana-dashboards/vps.json.tftpl", {
    prometheus_ds = local.prometheus_ds
  })
}

resource "grafana_dashboard" "website_traffic" {
  folder = grafana_folder.infrastructure.uid
  config_json = templatefile("${path.module}/grafana-dashboards/website-traffic.json.tftpl", {
    prometheus_ds = local.prometheus_ds
  })

  depends_on = [helm_release.ingress_nginx]
}

locals {
  service_ready_ratio = trimspace(file("${path.module}/grafana-dashboards/service-ready-ratio.promql"))
  service_uptime_expr = "avg_over_time(clamp_max(${local.service_ready_ratio}, 1)[7d:1m]) * 100"
}

resource "grafana_dashboard" "service_status" {
  folder = grafana_folder.infrastructure.uid
  config_json = templatefile("${path.module}/grafana-dashboards/service-status.json.tftpl", {
    prometheus_ds       = local.prometheus_ds
    service_ready_ratio = local.service_ready_ratio
    service_uptime_expr = local.service_uptime_expr
  })
}
