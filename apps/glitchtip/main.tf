locals {
  glitchtip_domain = "glitchtip.vinnel.cloud"
  glitchtip_url    = "https://${local.glitchtip_domain}"
  postgres_image   = "postgres:18-alpine@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2"
}

resource "kubernetes_namespace_v1" "glitchtip" {
  metadata {
    name = "glitchtip"
  }
}

resource "cloudflare_dns_record" "glitchtip_vinnel_cloud" {
  zone_id = var.zone_id
  name    = local.glitchtip_domain
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "glitchtip_secret_key" {
  length  = 64
  special = false
}

resource "random_password" "glitchtip_db_password" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "glitchtip_config" {
  metadata {
    name      = "glitchtip-config"
    namespace = kubernetes_namespace_v1.glitchtip.metadata[0].name
  }
  data = {
    "secret-key"  = random_password.glitchtip_secret_key.result
    "db-password" = random_password.glitchtip_db_password.result
    "database-url" = join("", [
      "postgres://glitchtip:",
      random_password.glitchtip_db_password.result,
      "@glitchtip-postgres.",
      kubernetes_namespace_v1.glitchtip.metadata[0].name,
      ".svc.cluster.local:5432/glitchtip?sslmode=disable",
    ])
    "email-url" = "smtp+tls://resend:${var.resend_api_key}@smtp.resend.com:587"
  }
}

resource "kubernetes_service_v1" "glitchtip_postgres" {
  metadata {
    name      = "glitchtip-postgres"
    namespace = kubernetes_namespace_v1.glitchtip.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "glitchtip-postgres"
    }
    port {
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_stateful_set_v1" "glitchtip_postgres" {
  metadata {
    name      = "glitchtip-postgres"
    namespace = kubernetes_namespace_v1.glitchtip.metadata[0].name
    labels = {
      app = "glitchtip-postgres"
    }
  }

  spec {
    replicas     = 1
    service_name = kubernetes_service_v1.glitchtip_postgres.metadata[0].name

    selector {
      match_labels = {
        app = "glitchtip-postgres"
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
    }

    template {
      metadata {
        labels = {
          app = "glitchtip-postgres"
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "postgres"
          image = local.postgres_image

          port {
            name           = "postgres"
            container_port = 5432
          }

          env {
            name  = "POSTGRES_USER"
            value = "glitchtip"
          }

          env {
            name  = "POSTGRES_DB"
            value = "glitchtip"
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.glitchtip_config.metadata[0].name
                key  = "db-password"
              }
            }
          }

          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "glitchtip", "-d", "glitchtip"]
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "glitchtip", "-d", "glitchtip"]
            }
            period_seconds        = 30
            timeout_seconds       = 5
            initial_delay_seconds = 30
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "10Gi"
          }
        }
      }
    }
  }
}

module "glitchtip_postgres_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [kubernetes_stateful_set_v1.glitchtip_postgres]

  name        = "glitchtip-postgres"
  namespace   = kubernetes_namespace_v1.glitchtip.metadata[0].name
  target_kind = "StatefulSet"
  target_name = kubernetes_stateful_set_v1.glitchtip_postgres.metadata[0].name
  update_mode = "Initial"
  container_policies = [
    { container_name = "postgres", min_memory = "128Mi", max_memory = "1Gi" },
  ]
}

resource "kubernetes_persistent_volume_claim_v1" "glitchtip_uploads" {
  metadata {
    name      = "glitchtip-uploads-pvc"
    namespace = kubernetes_namespace_v1.glitchtip.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "helm_release" "glitchtip" {
  name          = "glitchtip"
  repository    = "https://gitlab.com/api/v4/projects/16325141/packages/helm/stable"
  chart         = "glitchtip"
  version       = "9.0.1"
  namespace     = kubernetes_namespace_v1.glitchtip.metadata[0].name
  timeout       = 900
  wait          = true
  wait_for_jobs = true

  values = [
    yamlencode({
      image = {
        tag = "6.2.3@sha256:95e0e2d6b1bc18446902ae0cb47910cc55d7c0d6756ee901b0cd8dce9f8ef5a9"
      }
      glitchtip = {
        existingSecret    = kubernetes_secret_v1.glitchtip_config.metadata[0].name
        existingSecretKey = "secret-key"
        domain            = local.glitchtip_url
        database = {
          existingSecret    = kubernetes_secret_v1.glitchtip_config.metadata[0].name
          existingSecretKey = "database-url"
        }
      }
      podSecurityContext = {
        fsGroup = 5000
      }
      securityContext = {
        allowPrivilegeEscalation = false
        runAsNonRoot             = true
        runAsUser                = 5000
      }
      replicaCount = 1
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "1"
          memory = "768Mi"
        }
      }
      podAnnotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/port"   = "8000"
        "prometheus.io/path"   = "/metrics"
      }
      extraEnvVars = [
        {
          name = "EMAIL_URL"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret_v1.glitchtip_config.metadata[0].name
              key  = "email-url"
            }
          }
        },
        {
          name  = "DEFAULT_FROM_EMAIL"
          value = "alerts@vinnel.cloud"
        },
        {
          name  = "ENABLE_USER_REGISTRATION"
          value = "false"
        },
        {
          name  = "ENABLE_ORGANIZATION_CREATION"
          value = "false"
        },
        {
          name  = "ENABLE_ADMIN"
          value = "false"
        },
        {
          name  = "ENABLE_OPENAPI"
          value = "false"
        },
        {
          name  = "ENABLE_OBSERVABILITY_API"
          value = "true"
        },
        {
          name  = "ALLOWED_HOSTS"
          value = local.glitchtip_domain
        },
        {
          name  = "CSRF_TRUSTED_ORIGINS"
          value = local.glitchtip_url
        },
        {
          name  = "VTASKS_CONCURRENCY"
          value = "4"
        },
        {
          name  = "VTASKS_INGEST_CONCURRENCY"
          value = "4"
        },
        {
          name  = "DATABASE_POOL_MAX_SIZE"
          value = "5"
        },
      ]
      extraVolumes = [
        {
          name = "uploads"
          persistentVolumeClaim = {
            claimName = kubernetes_persistent_volume_claim_v1.glitchtip_uploads.metadata[0].name
          }
        },
      ]
      extraVolumeMounts = [
        {
          name      = "uploads"
          mountPath = "/code/uploads"
        },
      ]
      migrationJob = {
        extraInitContainers = [
          {
            name    = "wait-for-postgres"
            image   = local.postgres_image
            command = ["sh", "-c", "until pg_isready -h glitchtip-postgres -U glitchtip -d glitchtip; do sleep 2; done"]
          },
        ]
      }
      valkey = {
        enabled = true
        image = {
          tag = "9.1.1@sha256:70739f85ad2ee01a726a965584a0f94895f01b0c60b3cc8b0aeef11eaa6888cf"
        }
        dataStorage = {
          enabled = false
        }
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }
      ingress = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_stateful_set_v1.glitchtip_postgres]
}

resource "kubernetes_ingress_v1" "glitchtip_vinnel_cloud" {
  depends_on = [helm_release.glitchtip]

  metadata {
    name      = "glitchtip-vinnel-cloud"
    namespace = kubernetes_namespace_v1.glitchtip.metadata[0].name
    annotations = merge(var.admin_frame_service_annotations, {
      "cert-manager.io/cluster-issuer"                 = var.cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "40m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "60"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "60"
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [local.glitchtip_domain]
      secret_name = "glitchtip-vinnel-cloud-tls"
    }

    rule {
      host = local.glitchtip_domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "glitchtip-web"
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

resource "kubernetes_ingress_v1" "glitchtip_api_vinnel_cloud" {
  depends_on = [kubernetes_ingress_v1.glitchtip_vinnel_cloud]

  metadata {
    name      = "glitchtip-api-vinnel-cloud"
    namespace = kubernetes_namespace_v1.glitchtip.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "40m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "60"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "60"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [local.glitchtip_domain]
      secret_name = "glitchtip-vinnel-cloud-tls"
    }

    rule {
      host = local.glitchtip_domain
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = "glitchtip-web"
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

module "glitchtip_vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [helm_release.glitchtip]

  name        = "glitchtip-web"
  namespace   = kubernetes_namespace_v1.glitchtip.metadata[0].name
  target_kind = "Deployment"
  target_name = "glitchtip-web"
  update_mode = "Auto"
  container_policies = [
    { container_name = "glitchtip", min_memory = "256Mi", max_memory = "768Mi" },
  ]
}
