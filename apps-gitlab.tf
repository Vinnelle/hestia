resource "kubernetes_namespace_v1" "gitlab" {
  metadata {
    name = "gitlab"
  }
}

resource "cloudflare_dns_record" "gitlab_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "gitlab.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "gitlab_root_password" {
  length  = 32
  special = false
}

locals {
  gitlab_omnibus_config = join("\n", [
    "external_url 'https://gitlab.vinnel.cloud'",
    "registry['enable'] = false",
    "gitlab_rails['gitlab_shell_ssh_port'] = 2222",
    "letsencrypt['enable'] = false",
    "nginx['listen_port'] = 80",
    "nginx['listen_https'] = false",
    "nginx['proxy_set_headers'] = { 'X-Forwarded-Proto' => 'https', 'X-Forwarded-Ssl' => 'on' }",
    "gitlab_rails['monitoring_whitelist'] = ['127.0.0.0/8', '10.244.0.0/16']",
  ])

  gitlab_config_hash = sha256(join("", [
    random_password.gitlab_root_password.result,
    local.gitlab_omnibus_config,
  ]))
}

resource "kubernetes_persistent_volume_claim_v1" "gitlab_config" {
  metadata {
    name      = "gitlab-config-pvc"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
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

resource "kubernetes_persistent_volume_claim_v1" "gitlab_logs" {
  metadata {
    name      = "gitlab-logs-pvc"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
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

resource "kubernetes_persistent_volume_claim_v1" "gitlab_data" {
  metadata {
    name      = "gitlab-data-pvc"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
    annotations = {
      "volumeType" = "hostPath"
    }
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "gitlab" {
  metadata {
    name      = "gitlab"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
    labels = {
      app = "gitlab"
    }
  }

  spec {
    replicas                  = 1
    progress_deadline_seconds = 1200

    selector {
      match_labels = {
        app = "gitlab"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "gitlab"
        }
        annotations = {
          "config-hash" = local.gitlab_config_hash
        }
      }

      spec {
        enable_service_links = false

        container {
          name  = "gitlab"
          image = "gitlab/gitlab-ce:18.11.9-ce.0@sha256:1e89377a1c04b228a7d291a35889b4931342378cce0e2e2f33f908d303fe10b2"

          env {
            name  = "GITLAB_OMNIBUS_CONFIG"
            value = local.gitlab_omnibus_config
          }
          env {
            name  = "GITLAB_ROOT_EMAIL"
            value = var.acme_email_vin_moe
          }
          env {
            name  = "GITLAB_ROOT_PASSWORD"
            value = random_password.gitlab_root_password.result
          }

          port {
            name           = "http"
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "2000m"
              memory = "8Gi"
            }
            limits = {
              cpu    = "4000m"
              memory = "12Gi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/gitlab"
          }
          volume_mount {
            name       = "logs"
            mount_path = "/var/log/gitlab"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/opt/gitlab"
          }

          startup_probe {
            http_get {
              path = "/-/health"
              port = "http"
            }
            period_seconds        = 15
            failure_threshold     = 80
            initial_delay_seconds = 30
          }

          readiness_probe {
            http_get {
              path = "/-/readiness"
              port = "http"
            }
            period_seconds  = 10
            timeout_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/-/liveness"
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gitlab_config.metadata[0].name
          }
        }
        volume {
          name = "logs"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gitlab_logs.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gitlab_data.metadata[0].name
          }
        }
      }
    }
  }

  timeouts {
    create = "20m"
    update = "20m"
  }
}

resource "kubectl_manifest" "gitlab_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.gitlab]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "gitlab"
    namespace   = kubernetes_namespace_v1.gitlab.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.gitlab.metadata[0].name
    update_mode = "Initial"
    container_policies = [
      { container_name = "gitlab", min_memory = "4Gi", max_memory = "12Gi" },
    ]
  })
}

resource "kubernetes_service_v1" "gitlab" {
  metadata {
    name      = "gitlab"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "gitlab"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "gitlab_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx, kubernetes_deployment_v1.gitlab]
  metadata {
    name      = "gitlab-vinnel-cloud"
    namespace = kubernetes_namespace_v1.gitlab.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "0"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "300"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["gitlab.vinnel.cloud"]
      secret_name = "gitlab-vinnel-cloud-tls"
    }

    rule {
      host = "gitlab.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.gitlab.metadata[0].name
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
