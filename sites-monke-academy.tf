
resource "cloudflare_dns_record" "monke_academy_apex" {
  zone_id = data.cloudflare_zone.monke_academy.id
  name    = "monke.academy"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_ruleset" "monke_academy_cache" {
  zone_id = data.cloudflare_zone.monke_academy.id
  name    = "site cdn cache"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [{
    ref         = "cache_site"
    description = "cache everything for monke.academy"
    expression  = "http.host eq \"monke.academy\""
    action      = "set_cache_settings"
    action_parameters = {
      cache = true
    }
  }]
}

resource "kubectl_manifest" "letsencrypt_prod_monke_academy" {
  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.cloudflare_api_token]
  yaml_body = templatefile("${path.module}/manifests/cluster-issuer/cluster-issuer.yaml.tftpl", {
    issuer_name            = local.monke_academy_cluster_issuer
    email                  = var.acme_email_monke_academy
    cloudflare_secret_name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name
  })
}

resource "kubernetes_pod_disruption_budget_v1" "monke_academy_site" {
  metadata {
    name      = "monke-academy-site-pdb"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "monke-academy-site"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "monke_academy_site" {
  depends_on = [helm_release.harbor, harbor_project.monke_academy, kubernetes_secret_v1.registry_dockerconfig_websites]

  metadata {
    name      = "monke-academy-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    labels = {
      app = "monke-academy-site"
    }
  }

  spec {
    replicas          = 2
    min_ready_seconds = 10

    selector {
      match_labels = {
        app = "monke-academy-site"
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
          app = "monke-academy-site"
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
          image = local.images["monke-academy-site"]

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

resource "kubectl_manifest" "monke_academy_site_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.monke_academy_site]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "monke-academy-site"
    namespace   = kubernetes_namespace_v1.websites.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.monke_academy_site.metadata[0].name
    update_mode = "Auto"
    container_policies = [
      { container_name = "nginx", min_memory = "64Mi", max_memory = "256Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "monke_academy_site" {
  metadata {
    name      = "monke-academy-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "monke-academy-site"
    }
    port {
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_ingress_v1" "monke_academy_site" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "monke-academy-site"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.monke_academy_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["monke.academy"]
      secret_name = "monke-academy-tls"
    }

    rule {
      host = "monke.academy"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.monke_academy_site.metadata[0].name
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
