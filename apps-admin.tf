
resource "cloudflare_dns_record" "admin_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "admin.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_persistent_volume_claim_v1" "vinnel_cloud_admin_blog" {
  metadata {
    name      = "vinnel-cloud-admin-blog-pvc"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
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
  project      = gitlab_project.gaia.id
  name         = "vinnel-cloud-admin-blog"
  scopes       = ["api"]
  access_level = "developer"
  expires_at   = "2027-08-01"
}

resource "kubernetes_secret_v1" "vinnel_cloud_admin_blog" {
  metadata {
    name      = "vinnel-cloud-admin-blog"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  data = {
    GITLAB_TOKEN = gitlab_project_access_token.admin_blog.token
  }
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
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
}

resource "kubernetes_role_v1" "vinnel_cloud_admin_gameserver_scale" {
  metadata {
    name      = "vinnel-cloud-admin-gameserver-scale"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
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
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.vinnel_cloud_admin_gameserver_scale.metadata[0].name
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
  depends_on = [kubernetes_deployment_v1.gitlab, kubernetes_secret_v1.registry_dockerconfig_websites]

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

        volume {
          name = "blog"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vinnel_cloud_admin_blog.metadata[0].name
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

          env {
            name  = "SATISFACTORY_HOST"
            value = var.node_ip
          }

          env {
            name  = "SATISFACTORY_SAVES_URL"
            value = "http://${kubernetes_service_v1.satisfactory_saves.metadata[0].name}.${kubernetes_namespace_v1.server.metadata[0].name}.svc.cluster.local:8080"
          }

          env {
            name = "SATISFACTORY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.satisfactory_admin.metadata[0].name
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
            value = trimsuffix(cloudflare_dns_record.mc_vin_moe.name, ".")
          }

          env {
            name  = "MINECRAFT_RCON_ADDR"
            value = "${var.node_ip}:25575"
          }

          env {
            name = "MINECRAFT_RCON_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.minecraft_rcon_admin.metadata[0].name
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
            value = gitlab_branch.pre.name
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
            value = gitlab_project.gaia.id
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

module "vinnel_cloud_admin_vpa" {
  source = "./modules/vpa"

  depends_on = [helm_release.vpa, kubernetes_deployment_v1.vinnel_cloud_admin]

  name        = "vinnel-cloud-admin"
  namespace   = kubernetes_namespace_v1.websites.metadata[0].name
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
