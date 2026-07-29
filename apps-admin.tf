
resource "cloudflare_dns_record" "admin_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "admin.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_service_account_v1" "vinnel_cloud_admin" {
  metadata {
    name      = "vinnel-cloud-admin"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
}

resource "kubernetes_cluster_role_v1" "vinnel_cloud_admin" {
  metadata {
    name = "vinnel-cloud-admin-read"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "pods", "persistentvolumes", "persistentvolumeclaims"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = ["ceph.rook.io"]
    resources  = ["cephclusters"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "vinnel_cloud_admin" {
  metadata {
    name = "vinnel-cloud-admin-read"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.vinnel_cloud_admin.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vinnel_cloud_admin.metadata[0].name
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
}

resource "kubernetes_pod_disruption_budget_v1" "vinnel_cloud_admin" {
  metadata {
    name      = "vinnel-cloud-admin-pdb"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "vinnel-cloud-admin"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "vinnel_cloud_admin" {
  depends_on = [helm_release.harbor, harbor_project.vinnel_cloud, kubernetes_secret_v1.registry_dockerconfig_websites]

  metadata {
    name      = "vinnel-cloud-admin"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    labels = {
      app = "vinnel-cloud-admin"
    }
  }

  spec {

    replicas          = 2
    min_ready_seconds = 10

    selector {
      match_labels = {
        app = "vinnel-cloud-admin"
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "100%"
        max_unavailable = 0
      }
    }

    template {
      metadata {
        labels = {
          app = "vinnel-cloud-admin"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.vinnel_cloud_admin.metadata[0].name

        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig_websites.metadata[0].name
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          fs_group        = 10001
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "admin"
          image = local.images["vinnel-cloud-admin"]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 8080
          }

          env {
            name  = "OTEL_COLLECTOR_ENDPOINT"
            value = "signoz-otel-collector.${kubernetes_namespace_v1.monitoring.metadata[0].name}.svc.cluster.local:4317"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "128Mi"
            }
          }

          startup_probe {
            http_get {
              path = "/healthz"
              port = "8080"
            }
            period_seconds    = 5
            failure_threshold = 30
            timeout_seconds   = 2
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "8080"
            }
            period_seconds  = 5
            timeout_seconds = 2
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "8080"
            }
            period_seconds  = 10
            timeout_seconds = 2
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "vinnel_cloud_admin_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.vinnel_cloud_admin]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "vinnel-cloud-admin"
    namespace   = kubernetes_namespace_v1.websites.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.vinnel_cloud_admin.metadata[0].name
    update_mode = "Auto"
    container_policies = [
      { container_name = "admin", min_memory = "32Mi", max_memory = "128Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "vinnel_cloud_admin" {
  metadata {
    name      = "vinnel-cloud-admin"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "vinnel-cloud-admin"
    }
    port {
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_ingress_v1" "vinnel_cloud_admin" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "vinnel-cloud-admin"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = merge(local.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["admin.vinnel.cloud"]
      secret_name = "vinnel-cloud-admin-tls"
    }

    rule {
      host = "admin.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.vinnel_cloud_admin.metadata[0].name
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
