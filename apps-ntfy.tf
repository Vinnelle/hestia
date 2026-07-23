
resource "cloudflare_dns_record" "ntfy_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "ntfy.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "ntfy_admin" {
  length  = 24
  special = false
}

resource "random_password" "ntfy_publisher_password" {
  length  = 24
  special = false
}

resource "random_password" "ntfy_publisher_token" {
  length  = 29
  upper   = false
  special = false
}

locals {
  ntfy_publisher_token = "tk_${random_password.ntfy_publisher_token.result}"

  ntfy_config_yaml = yamlencode({
    "base-url"    = "https://ntfy.vinnel.cloud"
    "listen-http" = ":80"

    "behind-proxy" = true

    "cache-file"           = "/var/cache/ntfy/cache.db"
    "attachment-cache-dir" = "/var/cache/ntfy/attachments"

    "attachment-total-size-limit" = "1G"
    "attachment-file-size-limit"  = "50M"
    "attachment-expiry-duration"  = "72h"

    "auth-file"           = "/var/lib/ntfy/auth.db"
    "auth-default-access" = "deny-all"
    "enable-signup"       = false

    "auth-users" = [
      "ida:${random_password.ntfy_admin.bcrypt_hash}:admin",
      "publisher:${random_password.ntfy_publisher_password.bcrypt_hash}:user",
    ]
    "auth-tokens" = [
      "publisher:${local.ntfy_publisher_token}:grafana",
    ]
    "auth-access" = [
      "publisher:hestia-alerts:write-only",
    ]
  })
}

resource "kubernetes_secret_v1" "ntfy_config" {
  metadata {
    name      = "ntfy-config"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  data = {
    "server.yml" = local.ntfy_config_yaml
  }
}

resource "kubernetes_persistent_volume_claim_v1" "ntfy_cache" {
  metadata {
    name      = "ntfy-cache-pvc"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
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

resource "kubernetes_persistent_volume_claim_v1" "ntfy_auth" {
  metadata {
    name      = "ntfy-auth-pvc"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "64Mi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = kubernetes_deployment_v1.ntfy
  id = "services/ntfy"
}

resource "kubernetes_deployment_v1" "ntfy" {
  metadata {
    name      = "ntfy"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    labels = {
      app = "ntfy"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ntfy"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "ntfy"
        }
        annotations = {
          "ntfy-config-hash" = sha256(local.ntfy_config_yaml)
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "ntfy"
          image = "binwiederhier/ntfy:v2.26.3"
          args  = ["serve"]

          port {
            name           = "http"
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/ntfy"
            read_only  = true
          }

          volume_mount {
            name       = "cache"
            mount_path = "/var/cache/ntfy"
          }

          volume_mount {
            name       = "auth"
            mount_path = "/var/lib/ntfy"
          }

          readiness_probe {
            http_get {
              path = "/v1/health"
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/v1/health"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.ntfy_config.metadata[0].name
          }
        }

        volume {
          name = "cache"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.ntfy_cache.metadata[0].name
          }
        }

        volume {
          name = "auth"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.ntfy_auth.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "ntfy_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.ntfy]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "ntfy"
    namespace   = kubernetes_namespace_v1.services.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.ntfy.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "ntfy", min_memory = "32Mi", max_memory = "256Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "ntfy" {
  metadata {
    name      = "ntfy"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "ntfy"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "ntfy_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "ntfy-vinnel-cloud"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["ntfy.vinnel.cloud"]
      secret_name = "ntfy-vinnel-cloud-tls"
    }

    rule {
      host = "ntfy.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.ntfy.metadata[0].name
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
