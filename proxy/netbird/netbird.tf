resource "kubernetes_namespace_v1" "proxy" {
  metadata {
    name = "proxy"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "netbird_user" "ida" {
  role            = "admin"
  is_blocked      = false
  is_service_user = false
}

resource "netbird_account_settings" "main" {
  auto_update_version                    = "latest"
  dns_domain                             = ""
  groups_propagation_enabled             = true
  jwt_allow_groups                       = []
  jwt_groups_claim_name                  = ""
  jwt_groups_enabled                     = false
  lazy_connection_enabled                = false
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
  peers      = var.adguard_peer_ids
}

data "netbird_peer" "tv_1" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "tv-1"
}

resource "netbird_group" "iot" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "IoT"
  peers      = [data.netbird_peer.tv_1.id]
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
  depends_on  = [netbird_policy.devices_dns_udp_to_services, netbird_policy.devices_dns_tcp_to_services]
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
  zone_id = var.zone_id
  name    = "proxy.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "netbird_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "netbird.vinnel.cloud"
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
    namespace = kubernetes_namespace_v1.proxy.metadata[0].name
  }
  data = {
    relay-auth-secret            = random_password.netbird_relay_auth_secret.result
    dashboard-oidc-client-secret = var.dashboard_oidc_client_secret
  }
}

resource "kubernetes_ingress_v1" "netbird_dashboard_http" {
  metadata {
    name      = "netbird-dashboard-http"
    namespace = kubernetes_namespace_v1.proxy.metadata[0].name
    annotations = merge(var.admin_frame_service_annotations, {
      "cert-manager.io/cluster-issuer"                 = var.cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["netbird.vinnel.cloud"]
      secret_name = "netbird-dashboard-tls"
    }

    rule {
      host = "netbird.vinnel.cloud"
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

resource "kubernetes_ingress_v1" "netbird_api_http" {
  depends_on = [kubernetes_ingress_v1.netbird_dashboard_http]
  metadata {
    name      = "netbird-api-http"
    namespace = kubernetes_namespace_v1.proxy.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["netbird.vinnel.cloud"]
      secret_name = "netbird-dashboard-tls"
    }

    tls {
      hosts       = ["proxy.vinnel.cloud"]
      secret_name = "netbird-tls"
    }

    rule {
      host = "netbird.vinnel.cloud"
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.netbird_management_api.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    rule {
      host = "proxy.vinnel.cloud"
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.netbird_management_api.metadata[0].name
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
  metadata {
    name      = "netbird-grpc"
    namespace = kubernetes_namespace_v1.proxy.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                    = var.cluster_issuer
      "nginx.ingress.kubernetes.io/backend-protocol"      = "GRPC"
      "nginx.ingress.kubernetes.io/configuration-snippet" = "client_body_timeout 3600s;"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "86400"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "86400"
      "nginx.ingress.kubernetes.io/service-upstream"      = "true"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

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
