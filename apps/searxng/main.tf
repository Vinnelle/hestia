resource "kubernetes_namespace_v1" "searxng" {
  metadata {
    name = "searxng"
  }
}

resource "cloudflare_dns_record" "search_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "search.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "searxng_secret" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "searxng" {
  metadata {
    name      = "searxng"
    namespace = kubernetes_namespace_v1.searxng.metadata[0].name
  }
  data = {
    "secret-key" = random_password.searxng_secret.result
  }
}

resource "kubernetes_deployment_v1" "searxng" {
  metadata {
    name      = "searxng"
    namespace = kubernetes_namespace_v1.searxng.metadata[0].name
    labels = {
      app = "searxng"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "searxng"
      }
    }

    template {
      metadata {
        labels = {
          app = "searxng"
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "searxng"
          image = "searxng/searxng:2026.8.22-9fea41204"

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name  = "SEARXNG_BASE_URL"
            value = "https://search.vinnel.cloud/"
          }

          env {
            name = "SEARXNG_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.searxng.metadata[0].name
                key  = "secret-key"
              }
            }
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/searxng"
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "config"
          empty_dir {}
        }
      }
    }
  }
}

module "vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_deployment_v1.searxng]

  name        = "searxng"
  namespace   = kubernetes_namespace_v1.searxng.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.searxng.metadata[0].name
  update_mode = "Auto"
  container_policies = [
    { container_name = "searxng", min_memory = "128Mi", max_memory = "512Mi" },
  ]
}

resource "kubernetes_service_v1" "searxng" {
  metadata {
    name      = "searxng"
    namespace = kubernetes_namespace_v1.searxng.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "searxng"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "search_vinnel_cloud" {
  metadata {
    name      = "search-vinnel-cloud"
    namespace = kubernetes_namespace_v1.searxng.metadata[0].name
    annotations = merge(var.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["search.vinnel.cloud"]
      secret_name = "search-vinnel-cloud-tls"
    }

    rule {
      host = "search.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.searxng.metadata[0].name
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
