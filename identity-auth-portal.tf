resource "kubernetes_pod_disruption_budget_v1" "vinnel_cloud_auth" {
  metadata {
    name      = "vinnel-cloud-auth-pdb"
    namespace = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "vinnel-cloud-auth"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "vinnel_cloud_auth" {
  depends_on = [kubernetes_deployment_v1.gitlab, kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud]

  metadata {
    name      = "vinnel-cloud-auth"
    namespace = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
    labels = {
      app = "vinnel-cloud-auth"
    }
  }

  spec {
    replicas          = 2
    min_ready_seconds = 10

    selector {
      match_labels = {
        app = "vinnel-cloud-auth"
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
          app = "vinnel-cloud-auth"
        }
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud.metadata[0].name
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 101
          run_as_group    = 101
          fs_group        = 101
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "nginx"
          image = local.images["vinnel-cloud-auth"]

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "100m"
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

          lifecycle {
            pre_stop {
              exec {
                command = ["/bin/sh", "-c", "sleep 5"]
              }
            }
          }
        }
      }
    }
  }
}

module "vinnel_cloud_auth_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.vinnel_cloud_auth]

  name        = "vinnel-cloud-auth"
  namespace   = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.vinnel_cloud_auth.metadata[0].name
  update_mode = "Auto"
  container_policies = [
    { container_name = "nginx", min_memory = "32Mi", max_memory = "128Mi" },
  ]
}

resource "kubernetes_service_v1" "vinnel_cloud_auth" {
  metadata {
    name      = "vinnel-cloud-auth"
    namespace = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "vinnel-cloud-auth"
    }
    port {
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_ingress_v1" "vinnel_cloud_auth" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "vinnel-cloud-auth"
    namespace = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "auth.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.vinnel_cloud_auth.metadata[0].name
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
