
resource "cloudflare_dns_record" "vin_moe_apex" {
  zone_id = data.cloudflare_zone.vin_moe.id
  name    = "vin.moe"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_ruleset" "vin_moe_cache" {
  zone_id = data.cloudflare_zone.vin_moe.id
  name    = "site cdn cache"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [{
    ref         = "cache_site"
    description = "cache everything for vin.moe"
    expression  = "http.host eq \"vin.moe\""
    action      = "set_cache_settings"
    action_parameters = {
      cache = true
    }
  }]
}

resource "kubectl_manifest" "letsencrypt_prod_vin_moe" {
  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.cloudflare_api_token]
  yaml_body = templatefile("${path.module}/manifests/cluster-issuer/cluster-issuer.yaml.tftpl", {
    issuer_name            = local.vin_moe_cluster_issuer
    email                  = var.acme_email_vin_moe
    cloudflare_secret_name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name
  })
}

resource "kubernetes_pod_disruption_budget_v1" "vin_moe_site" {
  metadata {
    name      = "vin-moe-site-pdb"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "vin-moe-site"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "vin_moe_site" {
  depends_on = [helm_release.harbor, harbor_project.vin_moe, kubernetes_secret_v1.registry_dockerconfig_websites]

  metadata {
    name      = "vin-moe-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    labels = {
      app = "vin-moe-site"
    }
  }

  spec {
    replicas          = 2
    min_ready_seconds = 10

    selector {
      match_labels = {
        app = "vin-moe-site"
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
          app = "vin-moe-site"
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
          image = local.images["vin-moe-site"]

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "64Mi"
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

resource "kubectl_manifest" "vin_moe_site_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.vin_moe_site]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "vin-moe-site"
    namespace   = kubernetes_namespace_v1.websites.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.vin_moe_site.metadata[0].name
    update_mode = "Auto"
    container_policies = [
      { container_name = "nginx", min_memory = "16Mi", max_memory = "64Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "vin_moe_site" {
  metadata {
    name      = "vin-moe-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "vin-moe-site"
    }
    port {
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_ingress_v1" "vin_moe_site" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "vin-moe-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vin_moe_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["vin.moe"]
      secret_name = "vin-moe-tls"
    }

    rule {
      host = "vin.moe"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.vin_moe_site.metadata[0].name
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
