# Custom login front-end for Authelia (hestia/vinnel-cloud/auth) — replaces the
# stock React portal at auth.vinnel.cloud/ so the sign-in page matches the
# vinnel.cloud brand. Authelia itself is untouched: this page speaks its /api
# endpoints, and the SPA routes that still need the stock UI (/consent,
# /settings) stay routed to Authelia in identity-authelia.tf's ingress.
#
# Identity-domain resource, but it lives in the websites namespace: the image
# ships through site-deploy.yml, which hardcodes `-n websites` (same constraint
# as vinnel-cloud-admin, see apps-admin.tf).

resource "kubernetes_pod_disruption_budget_v1" "vinnel_cloud_auth" {
  metadata {
    name      = "vinnel-cloud-auth-pdb"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
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
  depends_on = [helm_release.harbor, harbor_project.vinnel_cloud, kubernetes_secret_v1.registry_dockerconfig_websites]

  metadata {
    name      = "vinnel-cloud-auth"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
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
          name = kubernetes_secret_v1.registry_dockerconfig_websites.metadata[0].name
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

resource "kubectl_manifest" "vinnel_cloud_auth_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.vinnel_cloud_auth]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "vinnel-cloud-auth"
    namespace   = kubernetes_namespace_v1.websites.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.vinnel_cloud_auth.metadata[0].name
    update_mode = "Auto"
    container_policies = [
      { container_name = "nginx", min_memory = "32Mi", max_memory = "128Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "vinnel_cloud_auth" {
  metadata {
    name      = "vinnel-cloud-auth"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
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

# Second ingress on the auth.vinnel.cloud host: it has to live in this service's
# namespace (websites) while Authelia's ingress stays in services — ingress-nginx
# merges both into one server block by hostname, longest path prefix wins. TLS
# for the host is declared once, on the Authelia ingress; adding a tls block
# here too would have two ingresses fighting over the certificate.
resource "kubernetes_ingress_v1" "vinnel_cloud_auth" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "vinnel-cloud-auth"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
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
