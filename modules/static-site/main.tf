resource "cloudflare_dns_record" "apex" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_dns_record" "extra" {
  for_each = toset(var.extra_hosts)

  zone_id = var.zone_id
  name    = each.value
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "site cdn cache"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [{
    ref         = "cache_site"
    description = var.cache_description
    expression  = join(" or ", [for h in concat([var.domain], var.extra_hosts) : format("http.host eq %q", h)])
    action      = "set_cache_settings"
    action_parameters = {
      cache = true
    }
  }]
}

resource "kubectl_manifest" "letsencrypt" {
  yaml_body = templatefile("${path.module}/cluster-issuer.yaml.tftpl", {
    issuer_name            = var.cluster_issuer
    email                  = var.acme_email
    cloudflare_secret_name = var.cloudflare_secret_name
  })
}

resource "kubernetes_pod_disruption_budget_v1" "this" {
  metadata {
    name      = "${var.site_slug}-site-pdb"
    namespace = var.namespace
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "${var.site_slug}-site"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = "${var.site_slug}-site"
    namespace = var.namespace
    labels = {
      app = "${var.site_slug}-site"
    }
  }

  spec {
    replicas          = var.replicas
    min_ready_seconds = 10

    selector {
      match_labels = {
        app = "${var.site_slug}-site"
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
          app = "${var.site_slug}-site"
        }
      }

      spec {
        image_pull_secrets {
          name = var.registry_secret_name
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
          image = var.image

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = var.port_name
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
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

module "vpa" {
  source = "../vpa"

  name        = "${var.site_slug}-site"
  namespace   = var.namespace
  target_kind = "Deployment"
  target_name = kubernetes_deployment_v1.this.metadata[0].name
  update_mode = var.vpa_update_mode
  container_policies = [
    { container_name = "nginx", min_memory = var.memory_request, max_memory = var.memory_limit },
  ]
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = "${var.site_slug}-site"
    namespace = var.namespace
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "${var.site_slug}-site"
    }
    port {
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_ingress_v1" "this" {
  metadata {
    name      = "${var.site_slug}-site"
    namespace = var.namespace
    annotations = {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = concat([var.domain], var.extra_hosts)
      secret_name = "${var.site_slug}-tls"
    }

    rule {
      host = var.domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.this.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    dynamic "rule" {
      for_each = toset(var.extra_hosts)

      content {
        host = rule.value
        http {
          path {
            path      = "/"
            path_type = "Prefix"
            backend {
              service {
                name = kubernetes_service_v1.this.metadata[0].name
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
