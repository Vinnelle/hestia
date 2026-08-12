
resource "cloudflare_dns_record" "shell_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "shell.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "shell_ttyd" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "shell_ttyd_credentials" {
  metadata {
    name      = "shell-ttyd-credentials"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
  data = {
    password = random_password.shell_ttyd.result
  }
}

resource "kubernetes_deployment_v1" "vinnel_cloud_shell" {
  depends_on = [helm_release.harbor, harbor_project.vinnel_cloud, kubernetes_secret_v1.registry_dockerconfig_websites]

  metadata {
    name      = "vinnel-cloud-shell"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    labels = {
      app = "vinnel-cloud-shell"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "vinnel-cloud-shell"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "vinnel-cloud-shell"
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
          name  = "shell"
          image = local.images["vinnel-cloud-shell"]

          command = ["sh", "-c"]
          args = [<<-EOT
            exec ttyd -p 7681 -W -c "ida:$(cat /secrets/password)" \
              -t 'theme={"background":"#0c0c0d","foreground":"#cececa","cursor":"#f7b9d1"}' \
              bash
          EOT
          ]

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "http"
            container_port = 7681
          }

          volume_mount {
            name       = "ttyd-credentials"
            mount_path = "/secrets"
            read_only  = true
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
            tcp_socket {
              port = "http"
            }
            period_seconds    = 5
            failure_threshold = 30
            timeout_seconds   = 2
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 5
            timeout_seconds = 2
          }

          liveness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 2
          }
        }

        volume {
          name = "ttyd-credentials"
          secret {
            secret_name = kubernetes_secret_v1.shell_ttyd_credentials.metadata[0].name
          }
        }
      }
    }
  }
}

module "vinnel_cloud_shell_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.vinnel_cloud_shell]

  name        = "vinnel-cloud-shell"
  namespace   = kubernetes_namespace_v1.websites.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.vinnel_cloud_shell.metadata[0].name
  update_mode = "Auto"
  container_policies = [
    { container_name = "shell", min_memory = "32Mi", max_memory = "128Mi" },
  ]
}

resource "kubernetes_service_v1" "vinnel_cloud_shell" {
  metadata {
    name      = "vinnel-cloud-shell"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "vinnel-cloud-shell"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "shell_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "shell-vinnel-cloud"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = merge(local.admin_framed_service_annotations["shell"], {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["shell.vinnel.cloud"]
      secret_name = "shell-vinnel-cloud-tls"
    }

    rule {
      host = "shell.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.vinnel_cloud_shell.metadata[0].name
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
