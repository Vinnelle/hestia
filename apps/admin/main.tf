resource "cloudflare_dns_record" "admin_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "admin.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_persistent_volume_claim_v1" "vinnel_cloud_admin_blog" {
  metadata {
    name      = "vinnel-cloud-admin-blog-pvc"
    namespace = var.namespace
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "gitlab_project_access_token" "admin_blog" {
  project      = var.gitlab_project_id
  name         = "vinnel-cloud-admin-blog"
  scopes       = ["api"]
  access_level = "developer"
  expires_at   = "2027-08-01"
}

resource "kubernetes_secret_v1" "vinnel_cloud_admin_blog" {
  metadata {
    name      = "vinnel-cloud-admin-blog"
    namespace = var.namespace
  }

  data = {
    GITLAB_TOKEN         = gitlab_project_access_token.admin_blog.token
    CF_CACHE_PURGE_TOKEN = var.cloudflare_cache_purge_token
  }
}

resource "kubernetes_service_account_v1" "vinnel_cloud_admin" {
  metadata {
    name      = "vinnel-cloud-admin"
    namespace = var.namespace
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
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes", "pods"]
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
    namespace = var.namespace
  }
}

resource "kubernetes_role_v1" "vinnel_cloud_admin_gameserver_scale" {
  metadata {
    name      = "vinnel-cloud-admin-gameserver-scale"
    namespace = var.games_namespace
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments/scale"]
    verbs      = ["get", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "vinnel_cloud_admin_gameserver_scale" {
  metadata {
    name      = "vinnel-cloud-admin-gameserver-scale"
    namespace = var.games_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.vinnel_cloud_admin_gameserver_scale.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.vinnel_cloud_admin.metadata[0].name
    namespace = var.namespace
  }
}

resource "kubernetes_pod_disruption_budget_v1" "vinnel_cloud_admin" {
  metadata {
    name      = "vinnel-cloud-admin-pdb"
    namespace = var.namespace
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

  metadata {
    name      = "vinnel-cloud-admin"
    namespace = var.namespace
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
          name = var.registry_secret_name
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

        volume {
          name = "blog"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vinnel_cloud_admin_blog.metadata[0].name
          }
        }

        container {
          name  = "admin"
          image = var.image

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
            value = "signoz-otel-collector.${var.observability_namespace}.svc.cluster.local:4317"
          }

          env {
            name  = "SENTRY_DSN"
            value = var.sentry_dsn
          }

          env {
            name  = "SENTRY_ENVIRONMENT"
            value = "production"
          }

          env {
            name  = "SATISFACTORY_HOST"
            value = var.node_ip
          }

          env {
            name  = "SATISFACTORY_SAVES_URL"
            value = "http://${var.satisfactory_saves_service_name}.${var.games_namespace}.svc.cluster.local:8080"
          }

          env {
            name = "SATISFACTORY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.satisfactory_admin_secret_name
                key  = "ADMIN_PASSWORD"
              }
            }
          }

          env {
            name  = "MINECRAFT_HOST"
            value = var.node_ip
          }

          env {
            name  = "MINECRAFT_ADDRESS"
            value = trimsuffix(var.minecraft_dns_record_name, ".")
          }

          env {
            name  = "MINECRAFT_RCON_ADDR"
            value = "${var.node_ip}:25575"
          }

          env {
            name = "MINECRAFT_RCON_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.minecraft_rcon_secret_name
                key  = "RCON_PASSWORD"
              }
            }
          }

          env {
            name  = "BLOG_DATA_DIR"
            value = "/data/posts"
          }

          env {
            name  = "BLOG_BRANCH"
            value = var.gitlab_default_branch
          }

          env {
            name  = "BLOG_POSTS_PATH"
            value = "hestia/sites/vin-moe/site/posts"
          }

          env {
            name  = "GITLAB_API_URL"
            value = "https://gitlab.vinnel.cloud/api/v4"
          }

          env {
            name  = "GITLAB_PROJECT_ID"
            value = var.gitlab_project_id
          }

          env {
            name = "GITLAB_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.vinnel_cloud_admin_blog.metadata[0].name
                key  = "GITLAB_TOKEN"
              }
            }
          }

          env {
            name  = "BLOG_SITE_URL"
            value = "https://vin.moe"
          }

          env {
            name  = "BLOG_PUBLIC_URL"
            value = "https://blog.vin.moe"
          }

          env {
            name  = "BLOG_ZONE_ID"
            value = var.blog_zone_id
          }

          env {
            name = "CF_CACHE_PURGE_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.vinnel_cloud_admin_blog.metadata[0].name
                key  = "CF_CACHE_PURGE_TOKEN"
              }
            }
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

          volume_mount {
            name       = "blog"
            mount_path = "/data"
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

resource "kubernetes_cron_job_v1" "vinnel_cloud_admin_blog_sync" {
  metadata {
    name      = "vinnel-cloud-admin-blog-sync"
    namespace = var.namespace
  }

  spec {
    schedule                      = "0 2 * * *"
    timezone                      = "Etc/UTC"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 3

    job_template {
      metadata {}
      spec {
        backoff_limit = 3

        template {
          metadata {}
          spec {
            restart_policy                  = "OnFailure"
            automount_service_account_token = false

            image_pull_secrets {
              name = var.registry_secret_name
            }

            security_context {
              run_as_non_root = true
              run_as_user     = 10001
              run_as_group    = 10001
              seccomp_profile {
                type = "RuntimeDefault"
              }
            }

            volume {
              name = "blog"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.vinnel_cloud_admin_blog.metadata[0].name
              }
            }

            container {
              name  = "blog-sync"
              image = var.image

              security_context {
                allow_privilege_escalation = false
                read_only_root_filesystem  = true
                capabilities {
                  drop = ["ALL"]
                }
              }

              env {
                name  = "ROLE"
                value = "blog-sync"
              }

              env {
                name  = "BLOG_DATA_DIR"
                value = "/data/posts"
              }

              env {
                name  = "BLOG_BRANCH"
                value = var.gitlab_default_branch
              }

              env {
                name  = "BLOG_POSTS_PATH"
                value = "hestia/sites/vin-moe/site/posts"
              }

              env {
                name  = "GITLAB_API_URL"
                value = "https://gitlab.vinnel.cloud/api/v4"
              }

              env {
                name  = "GITLAB_PROJECT_ID"
                value = var.gitlab_project_id
              }

              env {
                name = "GITLAB_TOKEN"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.vinnel_cloud_admin_blog.metadata[0].name
                    key  = "GITLAB_TOKEN"
                  }
                }
              }

              resources {
                requests = {
                  cpu    = "10m"
                  memory = "32Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "128Mi"
                }
              }

              volume_mount {
                name       = "blog"
                mount_path = "/data"
                read_only  = true
              }
            }
          }
        }
      }
    }
  }
}

module "vinnel_cloud_admin_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_deployment_v1.vinnel_cloud_admin]

  name        = "vinnel-cloud-admin"
  namespace   = var.namespace
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.vinnel_cloud_admin.metadata[0].name
  update_mode = "Auto"
  container_policies = [
    { container_name = "admin", min_memory = "32Mi", max_memory = "128Mi" },
  ]
}

resource "kubernetes_service_v1" "vinnel_cloud_admin" {
  metadata {
    name      = "vinnel-cloud-admin"
    namespace = var.namespace
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
  metadata {
    name      = "vinnel-cloud-admin"
    namespace = var.namespace
    annotations = merge(var.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

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
