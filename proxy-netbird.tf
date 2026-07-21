
removed {
  from = netbird_user.ida

  lifecycle {
    destroy = false
  }
}

resource "netbird_group" "devices" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "devices"
}

resource "netbird_group" "services" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "services"
}

# ── Mesh access policies ──────────────────────────────────────────────────────
# Least-privilege replacement for the account's built-in "Default" all-to-all
# policy (disabled below). devices reach services on exactly the two exposed
# surfaces — momus sshd and adguard DNS — and nothing initiates toward devices.
# One rule per policy: the management API rejects multi-rule policies.

resource "netbird_policy" "devices_ssh_to_services" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "devices-ssh-to-services"
  enabled    = true

  rule {
    name          = "devices-ssh-to-services"
    description   = "momus sshd"
    action        = "accept"
    bidirectional = false
    protocol      = "tcp"
    ports         = ["2222"]
    sources       = [netbird_group.devices.id]
    destinations  = [netbird_group.services.id]
  }
}

resource "netbird_policy" "devices_dns_udp_to_services" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "devices-dns-udp-to-services"
  enabled    = true

  rule {
    name          = "devices-dns-udp-to-services"
    description   = "adguard DNS (netbird_nameserver_group.adguard_devices)"
    action        = "accept"
    bidirectional = false
    protocol      = "udp"
    ports         = ["53"]
    sources       = [netbird_group.devices.id]
    destinations  = [netbird_group.services.id]
  }
}

resource "netbird_policy" "devices_dns_tcp_to_services" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "devices-dns-tcp-to-services"
  enabled    = true

  rule {
    name          = "devices-dns-tcp-to-services"
    description   = "adguard DNS truncated-response fallback"
    action        = "accept"
    bidirectional = false
    protocol      = "tcp"
    ports         = ["53"]
    sources       = [netbird_group.devices.id]
    destinations  = [netbird_group.services.id]
  }
}

# The built-in all-to-all policy, imported and pinned disabled so the explicit
# policies above are the only access paths. depends_on orders the allow rules
# ahead of the disable in a single apply, so mesh access never gaps.
data "netbird_group" "all" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "All"
}

data "netbird_policy" "default" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "Default"
}

import {
  to = netbird_policy.default
  id = data.netbird_policy.default.id
}

resource "netbird_policy" "default" {
  depends_on = [
    netbird_policy.devices_ssh_to_services,
    netbird_policy.devices_dns_udp_to_services,
    netbird_policy.devices_dns_tcp_to_services,
  ]
  name        = "Default"
  description = "This is a default rule that allows connections between all the resources"
  enabled     = false

  rule {
    name          = "Default"
    description   = "This is a default rule that allows connections between all the resources"
    action        = "accept"
    bidirectional = true
    protocol      = "all"
    sources       = [data.netbird_group.all.id]
    destinations  = [data.netbird_group.all.id]
  }
}

resource "cloudflare_dns_record" "proxy_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "proxy.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "random_password" "netbird_relay_auth_secret" {
  length  = 32
  special = false
}

resource "random_id" "netbird_datastore_enc_key" {
  byte_length = 32
}

resource "kubernetes_secret_v1" "netbird_secrets" {
  metadata {
    name      = "netbird-secrets"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
  }
  data = {
    relay-auth-secret            = random_password.netbird_relay_auth_secret.result
    dashboard-oidc-client-secret = random_password.netbird_dashboard_oidc_client_secret.result
  }
}

resource "kubernetes_ingress_v1" "netbird_http" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "netbird-http"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["proxy.vinnel.cloud"]
      secret_name = "netbird-tls"
    }

    rule {
      host = "proxy.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.netbird_dashboard.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.netbird_management.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/relay"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.netbird_relay.metadata[0].name
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

resource "kubernetes_ingress_v1" "netbird_grpc" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "netbird-grpc"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/backend-protocol"   = "GRPC"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "86400"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "86400"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["proxy.vinnel.cloud"]
      secret_name = "netbird-tls"
    }

    rule {
      host = "proxy.vinnel.cloud"
      http {
        path {
          path      = "/management.ManagementService/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.netbird_management.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/signalexchange.SignalExchange/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.netbird_signal.metadata[0].name
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
