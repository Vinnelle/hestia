resource "kubernetes_namespace_v1" "registry" {
  metadata {
    name = "registry"
  }
}

resource "cloudflare_dns_record" "mirror_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "mirror.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = false
}

resource "random_password" "registry_cache" {
  length  = 32
  special = false
}

locals {
  registry_cache_config_yaml = <<-EOT
    version: 0.1
    log:
      level: info
    storage:
      filesystem:
        rootdirectory: /var/lib/registry
    http:
      addr: :5000
      debug:
        addr: :5001
      headers:
        X-Content-Type-Options: [nosniff]
    proxy:
      remoteurl: https://registry-1.docker.io
      username: ${jsonencode(var.docker_hub_username)}
      password: ${jsonencode(var.docker_hub_access_token)}
    auth:
      htpasswd:
        realm: basic-realm
        path: /auth/htpasswd
    health:
      storagedriver:
        enabled: true
        interval: 10s
        threshold: 3
  EOT

  registry_cache_config_hash = sha256(join("", [
    local.registry_cache_config_yaml,
    random_password.registry_cache.bcrypt_hash,
  ]))
}

resource "kubernetes_secret_v1" "registry_cache_config" {
  metadata {
    name      = "registry-cache-config"
    namespace = kubernetes_namespace_v1.registry.metadata[0].name
  }
  data = {
    "config.yml" = local.registry_cache_config_yaml
    "htpasswd"   = "ci:${random_password.registry_cache.bcrypt_hash}"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "registry_cache" {
  metadata {
    name      = "registry-cache-pvc"
    namespace = kubernetes_namespace_v1.registry.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
  wait_until_bound = false
}

resource "kubernetes_deployment_v1" "registry_cache" {
  metadata {
    name      = "registry-cache"
    namespace = kubernetes_namespace_v1.registry.metadata[0].name
    labels = {
      app = "registry-cache"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "registry-cache"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "registry-cache"
        }
        annotations = {
          "config-hash" = local.registry_cache_config_hash
        }
      }

      spec {
        container {
          name  = "registry"
          image = "registry:3@sha256:1be55279f18a2fe1a74edf2664cac61c1bea305b7b4642dab412e7affdcb3e33"

          port {
            name           = "registry"
            container_port = 5000
          }
          port {
            name           = "debug"
            container_port = 5001
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/distribution/config.yml"
            sub_path   = "config.yml"
            read_only  = true
          }
          volume_mount {
            name       = "config"
            mount_path = "/auth/htpasswd"
            sub_path   = "htpasswd"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/registry"
          }

          readiness_probe {
            http_get {
              path = "/debug/health"
              port = "debug"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/debug/health"
              port = "debug"
            }
            period_seconds        = 30
            timeout_seconds       = 5
            initial_delay_seconds = 15
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.registry_cache_config.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.registry_cache.metadata[0].name
          }
        }
      }
    }
  }
}

module "registry_cache_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_deployment_v1.registry_cache]

  name        = "registry-cache"
  namespace   = kubernetes_namespace_v1.registry.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.registry_cache.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "registry", min_memory = "128Mi", max_memory = "1Gi" },
  ]
}

resource "kubernetes_service_v1" "registry_cache" {
  metadata {
    name      = "registry-cache"
    namespace = kubernetes_namespace_v1.registry.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "registry-cache"
    }
    port {
      name        = "registry"
      port        = 5000
      target_port = "registry"
    }
  }
}

resource "kubernetes_ingress_v1" "mirror_vinnel_cloud" {
  depends_on = [kubernetes_deployment_v1.registry_cache]
  metadata {
    name      = "mirror-vinnel-cloud"
    namespace = kubernetes_namespace_v1.registry.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = var.cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["mirror.vinnel.cloud"]
      secret_name = "mirror-vinnel-cloud-tls"
    }

    rule {
      host = "mirror.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.registry_cache.metadata[0].name
              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
}

resource "gitlab_project_variable" "registry_cache_user" {
  project   = var.gitlab_project_id
  key       = "REGISTRY_CACHE_USER"
  value     = "ci"
  masked    = false
  protected = false
}

resource "gitlab_project_variable" "registry_cache_password" {
  project   = var.gitlab_project_id
  key       = "REGISTRY_CACHE_PASSWORD"
  value     = random_password.registry_cache.result
  masked    = true
  protected = false
}
