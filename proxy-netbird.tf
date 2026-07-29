
import {
  to = netbird_user.ida
  id = "602cdb07-d95e-4014-8361-1c24136a8a25"
}

resource "netbird_user" "ida" {
  role            = "admin"
  is_blocked      = false
  is_service_user = false
}

import {
  to = netbird_account_settings.main
  id = "d9jkfom7tkps73ehoj6g"
}

resource "netbird_account_settings" "main" {
  auto_update_version                    = "latest"
  dns_domain                             = ""
  groups_propagation_enabled             = true
  jwt_allow_groups                       = []
  jwt_groups_claim_name                  = ""
  jwt_groups_enabled                     = false
  lazy_connection_enabled                = true
  network_range                          = "100.64.0.0/16"
  network_traffic_logs_enabled           = false
  network_traffic_packet_counter_enabled = false
  peer_approval_enabled                  = false
  peer_expose_enabled                    = false
  peer_inactivity_expiration             = 600
  peer_inactivity_expiration_enabled     = false
  peer_login_expiration                  = 86400
  peer_login_expiration_enabled          = false
  regular_users_view_blocked             = true
  routing_peer_dns_resolution_enabled    = true
  user_approval_required                 = false
}

resource "netbird_group" "devices" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "User Devices"
}

resource "netbird_group" "adguard" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "Adguard"
  peers      = [for ordinal in sort(keys(data.netbird_peer.adguard)) : data.netbird_peer.adguard[ordinal].id]
}

resource "netbird_group" "servers" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "Servers"
  peers      = [data.netbird_peer.momus.id]
}

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
    destinations  = [netbird_group.servers.id]
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
    destinations  = [netbird_group.adguard.id]
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
    destinations  = [netbird_group.adguard.id]
  }
}

data "netbird_group" "all" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "All"
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

# Split from the API paths below so the dashboard can sit behind Authelia. /api
# and /relay must NOT inherit that: every peer and the netbird CLI talk to them,
# and a forward-auth redirect would brick the mesh. Annotations are per-Ingress
# in ingress-nginx, hence two objects.
#
# Plain forward-auth, NOT admin_framed_service_annotations: netbird is marked
# Frameable=false in vinnel-cloud/admin/services.go, so the portal opens it in a
# new tab and that navigation is a top-level document — the Sec-Fetch-Dest bounce
# would send it straight back to vinnel.cloud.
#
# Known wrinkle: /nb-silent-auth (the dashboard's hidden-iframe token renewal)
# lives under / and so is gated too. If the Authelia session ever lapses, renewal
# redirects to a login page inside that hidden iframe and fails quietly rather
# than erroring. The portal keeps the session warm, so this should not surface.
resource "kubernetes_ingress_v1" "netbird_dashboard_http" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "netbird-dashboard-http"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = merge(local.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer"                 = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    })
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
      }
    }
  }
}

# Machine plane: netbird peers and the CLI. No forward-auth, no Sec-Fetch bounce.
# cert-manager.io/cluster-issuer is deliberately absent — netbird_dashboard_http
# above owns the netbird-tls secret. Two Ingresses claiming the same secret for
# the same host would have two Certificates contending over it.
resource "kubernetes_ingress_v1" "netbird_api_http" {
  depends_on = [helm_release.ingress_nginx, kubernetes_ingress_v1.netbird_dashboard_http]
  metadata {
    name      = "netbird-api-http"
    namespace = kubernetes_namespace_v1.services.metadata[0].name
    annotations = {
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
