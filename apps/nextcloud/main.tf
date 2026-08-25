resource "kubernetes_namespace_v1" "files" {
  metadata {
    name = "files"
  }
}

resource "cloudflare_dns_record" "cloud_vinnel_cloud" {
  zone_id = var.zone_id
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
    namespace = kubernetes_namespace_v1.files.metadata[0].name
  }
  data = {
    "10-configure.sh" = local.nextcloud_setup_sh
  }
}

resource "kubernetes_secret_v1" "nextcloud_secrets" {
  metadata {
    name      = "nextcloud-secrets"
    namespace = kubernetes_namespace_v1.files.metadata[0].name
  }
  data = {
    "admin-password"     = random_password.nextcloud_admin_password.result
    "oidc-client-secret" = random_password.nextcloud_oidc_client_secret.result
    "s3-access-key"      = var.seaweedfs_s3_access_key
    "s3-secret-key"      = var.seaweedfs_s3_secret_key
    "mega-import-user"   = var.mega_import_user
    "mega-import-pass"   = var.mega_import_pass
  }
}

resource "kubernetes_persistent_volume_claim_v1" "nextcloud" {
  metadata {
    name      = "nextcloud-pvc"
    namespace = kubernetes_namespace_v1.files.metadata[0].name
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
    namespace = kubernetes_namespace_v1.files.metadata[0].name
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

          env {
            name  = "OBJECTSTORE_S3_BUCKET"
            value = "nextcloud-primary"
          }

          env {
            name  = "OBJECTSTORE_S3_HOST"
            value = "seaweedfs.storage.svc.cluster.local"
          }

          env {
            name  = "OBJECTSTORE_S3_PORT"
            value = "8333"
          }

          env {
            name  = "OBJECTSTORE_S3_SSL"
            value = "false"
          }

          env {
            name  = "OBJECTSTORE_S3_USEPATH_STYLE"
            value = "true"
          }

          env {
            name  = "OBJECTSTORE_S3_REGION"
            value = "us-east-1"
          }

          env {
            name = "OBJECTSTORE_S3_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "s3-access-key"
              }
            }
          }

          env {
            name = "OBJECTSTORE_S3_SECRET"
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
              memory = "4Gi"
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
              http_header {
                name  = "Host"
                value = "cloud.vinnel.cloud"
              }
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 18
          }

          liveness_probe {
            http_get {
              path = "/status.php"
              port = "http"
              http_header {
                name  = "Host"
                value = "cloud.vinnel.cloud"
              }
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

module "nextcloud_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_deployment_v1.nextcloud]

  name        = "nextcloud"
  namespace   = kubernetes_namespace_v1.files.metadata[0].name
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.nextcloud.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "nextcloud", min_memory = "256Mi", max_memory = "4Gi" },
  ]
}

resource "kubernetes_service_v1" "nextcloud" {
  metadata {
    name      = "nextcloud"
    namespace = kubernetes_namespace_v1.files.metadata[0].name
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
  metadata {
    name      = "cloud-vinnel-cloud"
    namespace = kubernetes_namespace_v1.files.metadata[0].name
    annotations = merge(var.admin_frame_service_annotations, {
      "cert-manager.io/cluster-issuer"              = var.cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

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

locals {
  nextcloud_mega_import_sh = <<-EOT
    set -eu
    cat > /tmp/rclone.conf <<CONF
    [mega-src]
    type = mega
    user = $MEGA_USER
    pass = $(rclone obscure "$MEGA_PASS")

    [nextcloud-dst]
    type = webdav
    url = $NEXTCLOUD_URL
    vendor = nextcloud
    user = $NEXTCLOUD_USER
    pass = $(rclone obscure "$NEXTCLOUD_PASS")
    CONF
    rclone sync mega-src: nextcloud-dst:/mega-import --config /tmp/rclone.conf --transfers 4 --checkers 8
  EOT
}

resource "kubernetes_job_v1" "nextcloud_mega_import" {
  depends_on = [kubernetes_ingress_v1.cloud_api_vinnel_cloud]

  metadata {
    name      = "nextcloud-mega-import"
    namespace = kubernetes_namespace_v1.files.metadata[0].name
  }

  spec {
    backoff_limit = 0

    template {
      metadata {}
      spec {
        restart_policy = "Never"

        container {
          name    = "import"
          image   = "rclone/rclone:1.75.0"
          command = ["sh", "-c", local.nextcloud_mega_import_sh]

          env {
            name = "MEGA_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "mega-import-user"
              }
            }
          }

          env {
            name = "MEGA_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "mega-import-pass"
              }
            }
          }

          env {
            name  = "NEXTCLOUD_URL"
            value = "https://cloud.vinnel.cloud/remote.php/dav/files/ida"
          }

          env {
            name  = "NEXTCLOUD_USER"
            value = "ida"
          }

          env {
            name = "NEXTCLOUD_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.nextcloud_secrets.metadata[0].name
                key  = "admin-password"
              }
            }
          }
        }
      }
    }
  }

  wait_for_completion = false
}

resource "kubernetes_ingress_v1" "cloud_api_vinnel_cloud" {
  depends_on = [kubernetes_ingress_v1.cloud_vinnel_cloud]
  metadata {
    name      = "cloud-api-vinnel-cloud"
    namespace = kubernetes_namespace_v1.files.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["cloud.vinnel.cloud"]
      secret_name = "cloud-vinnel-cloud-tls"
    }

    rule {
      host = "cloud.vinnel.cloud"
      http {
        dynamic "path" {
          for_each = ["/remote.php/", "/dav/", "/ocs/", "/public.php/", "/s/", "/index.php/s/", "/login/v2", "/index.php/login/v2", "/status.php", "/index.php/204", "/.well-known/"]
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
