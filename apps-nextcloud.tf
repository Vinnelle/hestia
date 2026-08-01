
resource "kubernetes_namespace_v1" "nextcloud" {
  metadata {
    name = "nextcloud"
  }
}

resource "cloudflare_dns_record" "cloud_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "cloud.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "nextcloud_admin_password" {
  length  = 24
  special = true
}

resource "random_password" "nextcloud_oidc_client_secret" {
  length  = 32
  special = false
}

locals {
  nextcloud_setup_sh = <<-EOT
    #!/bin/sh
    set -e
    occ() {
      php /var/www/html/occ "$@"
    }

    occ app:enable user_oidc || true

    occ theming:config name "vinnel.cloud"
    occ theming:config primary_color "#b3466b"
    occ theming:config background_color "#faf8f5"
    occ theming:config background backgroundColor

    if ! occ user_oidc:provider authelia >/dev/null 2>&1; then
      occ user_oidc:provider authelia \
        --clientid="nextcloud" \
        --clientsecret="$OIDC_CLIENT_SECRET" \
        --discoveryuri="https://auth.vinnel.cloud/.well-known/openid-configuration"
    fi

    occ app:enable files_external || true

    if ! occ files_external:list | grep -q "SeaweedFS"; then
      occ files_external:create "SeaweedFS" amazons3 amazons3::accesskey \
        --config bucket="nextcloud" \
        --config hostname="s3.vinnel.cloud" \
        --config port="443" \
        --config region="us-east-1" \
        --config use_ssl="true" \
        --config use_path_style="true" \
        --config key="$S3_ACCESS_KEY" \
        --config secret="$S3_SECRET_KEY"
    fi
  EOT
}

resource "kubernetes_config_map_v1" "nextcloud_setup" {
  metadata {
    name      = "nextcloud-setup"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
  }
  data = {
    "10-configure.sh" = local.nextcloud_setup_sh
  }
}

resource "kubernetes_secret_v1" "nextcloud_secrets" {
  metadata {
    name      = "nextcloud-secrets"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
  }
  data = {
    "admin-password"     = random_password.nextcloud_admin_password.result
    "oidc-client-secret" = random_password.nextcloud_oidc_client_secret.result
    "s3-access-key"      = random_password.seaweedfs_s3_access_key.result
    "s3-secret-key"      = random_password.seaweedfs_s3_secret_key.result
  }
}

resource "kubernetes_persistent_volume_claim_v1" "nextcloud" {
  metadata {
    name      = "nextcloud-pvc"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
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

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "nextcloud" {
  metadata {
    name      = "nextcloud"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
    labels = {
      app = "nextcloud"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nextcloud"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "nextcloud"
        }
        annotations = {
          "nextcloud-setup-hash" = sha256(local.nextcloud_setup_sh)
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "nextcloud"
          image = "nextcloud:34-apache"

          port {
            name           = "http"
            container_port = 80
          }

          env {
            name  = "SQLITE_DATABASE"
            value = "nextcloud"
          }

          env {
            name  = "NEXTCLOUD_ADMIN_USER"
            value = "ida"
          }

          env {
            name = "NEXTCLOUD_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "admin-password"
              }
            }
          }

          env {
            name  = "NEXTCLOUD_TRUSTED_DOMAINS"
            value = "cloud.vinnel.cloud"
          }

          env {
            name  = "OVERWRITEPROTOCOL"
            value = "https"
          }

          env {
            name  = "TRUSTED_PROXIES"
            value = "10.244.0.0/16"
          }

          env {
            name = "OIDC_CLIENT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "oidc-client-secret"
              }
            }
          }

          env {
            name = "S3_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "s3-access-key"
              }
            }
          }

          env {
            name = "S3_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "s3-secret-key"
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/www/html"
          }

          volume_mount {
            name       = "setup-hook"
            mount_path = "/docker-entrypoint-hooks.d/before-starting/10-configure.sh"
            sub_path   = "10-configure.sh"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/status.php"
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 18
          }

          liveness_probe {
            http_get {
              path = "/status.php"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.nextcloud.metadata[0].name
          }
        }

        volume {
          name = "setup-hook"
          config_map {
            name         = kubernetes_config_map_v1.nextcloud_setup.metadata[0].name
            default_mode = "0555"
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "nextcloud_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.nextcloud]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "nextcloud"
    namespace   = kubernetes_namespace_v1.nextcloud.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.nextcloud.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "nextcloud", min_memory = "256Mi", max_memory = "1Gi" },
    ]
  })
}

resource "kubernetes_service_v1" "nextcloud" {
  metadata {
    name      = "nextcloud"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "nextcloud"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "cloud_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "cloud-vinnel-cloud"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
    annotations = merge(local.admin_framed_service_annotations["cloud"], {
      "cert-manager.io/cluster-issuer"              = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["cloud.vinnel.cloud"]
      secret_name = "cloud-vinnel-cloud-tls"
    }

    rule {
      host = "cloud.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.nextcloud.metadata[0].name
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

resource "kubernetes_ingress_v1" "cloud_api_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx, kubernetes_ingress_v1.cloud_vinnel_cloud]
  metadata {
    name      = "cloud-api-vinnel-cloud"
    namespace = kubernetes_namespace_v1.nextcloud.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["cloud.vinnel.cloud"]
      secret_name = "cloud-vinnel-cloud-tls"
    }

    rule {
      host = "cloud.vinnel.cloud"
      http {
        dynamic "path" {
          for_each = ["/remote.php/", "/dav/", "/ocs/", "/public.php/", "/s/", "/index.php/s/", "/status.php", "/.well-known/"]
          content {
            path      = path.value
            path_type = "Prefix"
            backend {
              service {
                name = kubernetes_service_v1.nextcloud.metadata[0].name
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
}
