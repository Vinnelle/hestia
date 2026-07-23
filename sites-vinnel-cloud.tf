
resource "cloudflare_dns_record" "vinnel_cloud_apex" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_ruleset" "vinnel_cloud_cache" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "site cdn cache"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [{
    ref         = "cache_site"
    description = "cache everything for vinnel.cloud site"
    expression  = "http.host eq \"vinnel.cloud\""
    action      = "set_cache_settings"
    action_parameters = {
      cache = true
    }
  }]
}

resource "kubectl_manifest" "letsencrypt_prod_vinnel_cloud" {
  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.cloudflare_api_token]
  yaml_body = templatefile("${path.module}/manifests/cluster-issuer/cluster-issuer.yaml.tftpl", {
    issuer_name            = local.vinnel_cloud_cluster_issuer
    email                  = var.acme_email_vinnel_cloud
    cloudflare_secret_name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name
  })
}

resource "kubernetes_pod_disruption_budget_v1" "vinnel_cloud_site" {
  metadata {
    name      = "vinnel-cloud-site-pdb"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "vinnel-cloud-site"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "vinnel_cloud_site" {
  depends_on = [helm_release.harbor, harbor_project.vinnel_cloud, kubernetes_secret_v1.registry_dockerconfig_websites]

  metadata {
    name      = "vinnel-cloud-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    labels = {
      app = "vinnel-cloud-site"
    }
  }

  spec {
    replicas          = 2
    min_ready_seconds = 10

    selector {
      match_labels = {
        app = "vinnel-cloud-site"
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
          app = "vinnel-cloud-site"
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
          image = local.images["vinnel-cloud-site"]

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
              cpu    = "250m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
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

resource "kubectl_manifest" "vinnel_cloud_site_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.vinnel_cloud_site]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "vinnel-cloud-site"
    namespace   = kubernetes_namespace_v1.websites.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.vinnel_cloud_site.metadata[0].name
    update_mode = "Auto"
    container_policies = [
      { container_name = "nginx", min_memory = "64Mi", max_memory = "256Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "vinnel_cloud_site" {
  metadata {
    name      = "vinnel-cloud-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "vinnel-cloud-site"
    }
    port {
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_ingress_v1" "vinnel_cloud_site" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "vinnel-cloud-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["vinnel.cloud"]
      secret_name = "vinnel-cloud-tls"
    }

    rule {
      host = "vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.vinnel_cloud_site.metadata[0].name
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


resource "cloudflare_dns_record" "vinnel_cloud_dashboard" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "dashboard.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "kubernetes_secret_v1" "vinnel_cloud_dashboard_oidc" {
  metadata {
    name      = "vinnel-cloud-dashboard-oidc"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
  data = {
    client_secret = random_password.vinnel_cloud_dashboard_oidc_client_secret.result
    cookie_secret = random_password.vinnel_cloud_dashboard_cookie_secret.result
  }
}

resource "kubernetes_persistent_volume_claim_v1" "vinnel_cloud_dashboard" {
  metadata {
    name      = "vinnel-cloud-dashboard-pvc"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
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

resource "kubernetes_pod_disruption_budget_v1" "vinnel_cloud_dashboard" {
  metadata {
    name      = "vinnel-cloud-dashboard-pdb"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "vinnel-cloud-dashboard"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "vinnel_cloud_dashboard" {
  depends_on = [helm_release.harbor, harbor_project.vinnel_cloud, kubernetes_secret_v1.registry_dockerconfig_websites]

  metadata {
    name      = "vinnel-cloud-dashboard"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    labels = {
      app = "vinnel-cloud-dashboard"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "vinnel-cloud-dashboard"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "vinnel-cloud-dashboard"
        }
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig_websites.metadata[0].name
        }

        security_context {
          fs_group        = 10001
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "dashboard"
          image = local.images["vinnel-cloud-dashboard"]

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            container_port = 8080
          }

          env {
            name  = "OIDC_ISSUER"
            value = "https://auth.vinnel.cloud"
          }
          env {
            name  = "OIDC_CLIENT_ID"
            value = "vinnel-cloud-dashboard"
          }
          env {
            name = "OIDC_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.vinnel_cloud_dashboard_oidc.metadata[0].name
                key  = "client_secret"
              }
            }
          }
          env {
            name = "COOKIE_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.vinnel_cloud_dashboard_oidc.metadata[0].name
                key  = "cookie_secret"
              }
            }
          }
          env {
            name  = "BASE_URL"
            value = "https://dashboard.vinnel.cloud"
          }
          env {
            name  = "DB_PATH"
            value = "/data/dashboard.db"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
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

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.vinnel_cloud_dashboard.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "vinnel_cloud_dashboard" {
  metadata {
    name      = "vinnel-cloud-dashboard"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "vinnel-cloud-dashboard"
    }
    port {
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_ingress_v1" "vinnel_cloud_dashboard" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "vinnel-cloud-dashboard"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["dashboard.vinnel.cloud"]
      secret_name = "vinnel-cloud-dashboard-tls"
    }

    rule {
      host = "dashboard.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.vinnel_cloud_dashboard.metadata[0].name
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
