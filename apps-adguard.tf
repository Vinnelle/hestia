
resource "kubernetes_namespace_v1" "adguard" {
  metadata {
    name = "adguard"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "cloudflare_dns_record" "adguard_admin_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "adguard.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

locals {
  adguard_config_template_yaml = yamlencode({
    schema_version = 29
    http = {
      address = "0.0.0.0:3000"
    }
    # Authelia forward-auth guards the ingress (see the merged annotations on
    # the ingress below) — no local users, or the UI prompts for its own login
    # on top of Authelia's.
    users = []
    dns = {
      bind_hosts          = ["0.0.0.0"]
      port                = 53
      anonymize_client_ip = true
      upstream_dns = [
        "https://dns.quad9.net/dns-query",
        "https://cloudflare-dns.com/dns-query",
      ]
      bootstrap_dns = [
        "9.9.9.9",
        "149.112.112.112",
        "1.1.1.1",
        "1.0.0.1",
      ]
      fallback_dns = [
        "9.9.9.9",
        "149.112.112.112",
        "1.1.1.1",
        "1.0.0.1",
      ]
    }
  })
  adguard_config_template_hash = sha256(local.adguard_config_template_yaml)
}

resource "kubernetes_config_map_v1" "adguard_config_template" {
  metadata {
    name      = "adguard-config-template"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  data = {
    "AdGuardHome.yaml" = local.adguard_config_template_yaml
  }
}

resource "netbird_setup_key" "adguard" {
  depends_on     = [cloudflare_dns_record.proxy_vinnel_cloud]
  name           = "adguard"
  type           = "one-off"
  expiry_seconds = 3600
  ephemeral      = false
  usage_limit    = 1
  auto_groups    = [netbird_group.services.id]
}

resource "kubernetes_secret_v1" "adguard_netbird_setup_key" {
  metadata {
    name      = "adguard-netbird-setup-key"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  data = {
    setup-key = netbird_setup_key.adguard.key
  }
}

resource "kubernetes_persistent_volume_claim_v1" "adguard_conf" {
  metadata {
    name      = "adguard-conf-pvc"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "256Mi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim_v1" "adguard_work" {
  metadata {
    name      = "adguard-work-pvc"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim_v1" "adguard_netbird_state" {
  metadata {
    name      = "adguard-netbird-state-pvc"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "64Mi"
      }
    }
  }
  wait_until_bound = false

  # losing netbird state re-registers the peer under a new mesh IP, which the
  # nameserver group below would then point at stale
  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_deployment_v1" "adguard" {
  metadata {
    name      = "adguard"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
    labels = {
      app = "adguard"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "adguard"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "adguard"
        }
        annotations = {
          "adguard-config-hash" = local.adguard_config_template_hash
        }
      }

      spec {
        enable_service_links = false

        init_container {
          name    = "seed-config"
          image   = "docker.io/library/busybox:1.38.0"
          command = ["sh", "-c", file("${path.module}/adguard/seed-config.sh")]

          env {
            name  = "TEMPLATE_HASH"
            value = local.adguard_config_template_hash
          }

          volume_mount {
            name       = "template"
            mount_path = "/template"
            read_only  = true
          }

          volume_mount {
            name       = "conf"
            mount_path = "/conf"
          }
        }

        container {
          name  = "adguard"
          image = "adguard/adguardhome:v0.107.78"

          port {
            name           = "http"
            container_port = 3000
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "conf"
            mount_path = "/opt/adguardhome/conf"
          }

          volume_mount {
            name       = "work"
            mount_path = "/opt/adguardhome/work"
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            tcp_socket {
              port = "http"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        container {
          name  = "netbird"
          image = "netbirdio/netbird:0.74.3"

          env {
            name = "NB_SETUP_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.adguard_netbird_setup_key.metadata[0].name
                key  = "setup-key"
              }
            }
          }

          env {
            name  = "NB_MANAGEMENT_URL"
            value = "https://proxy.vinnel.cloud"
          }

          env {
            name  = "NB_HOSTNAME"
            value = "adguard"
          }

          env {
            name  = "NB_DISABLE_DNS"
            value = "true"
          }

          security_context {
            capabilities {
              # NET_ADMIN + /dev/net/tun is what the wireguard tunnel needs;
              # SYS_RESOURCE covers rlimit bumps. SYS_ADMIN is near-root and
              # deliberately not granted.
              add = ["NET_ADMIN", "SYS_RESOURCE"]
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "dev-net-tun"
            mount_path = "/dev/net/tun"
          }

          volume_mount {
            name       = "netbird-state"
            mount_path = "/var/lib/netbird"
          }
        }

        volume {
          name = "template"
          config_map {
            name = kubernetes_config_map_v1.adguard_config_template.metadata[0].name
          }
        }

        volume {
          name = "conf"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.adguard_conf.metadata[0].name
          }
        }

        volume {
          name = "work"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.adguard_work.metadata[0].name
          }
        }

        volume {
          name = "netbird-state"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.adguard_netbird_state.metadata[0].name
          }
        }

        volume {
          name = "dev-net-tun"
          host_path {
            path = "/dev/net/tun"
            type = "CharDevice"
          }
        }
      }
    }
  }
}

resource "kubectl_manifest" "adguard_vpa" {
  depends_on = [helm_release.vpa, kubernetes_deployment_v1.adguard]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "adguard"
    namespace   = kubernetes_namespace_v1.adguard.metadata[0].name
    target_kind = "Deployment"
    target_name = kubernetes_deployment_v1.adguard.metadata[0].name
    update_mode = "Initial" # single replica, Recreate: Auto-mode evictions would drop device DNS at random times
    container_policies = [
      { container_name = "adguard", min_memory = "64Mi", max_memory = "512Mi" },
      { container_name = "netbird", min_memory = "16Mi", max_memory = "128Mi" },
    ]
  })
}

resource "kubernetes_service_v1" "adguard" {
  metadata {
    name      = "adguard"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "adguard"
    }
    port {
      port        = 80
      target_port = "http"
    }
  }
}

resource "kubernetes_ingress_v1" "adguard_admin_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx]
  metadata {
    name      = "adguard-admin-vinnel-cloud"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
    annotations = merge(local.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["adguard.vinnel.cloud"]
      secret_name = "adguard-vinnel-cloud-tls"
    }

    rule {
      host = "adguard.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.adguard.metadata[0].name
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


data "netbird_peer" "adguard" {
  depends_on = [kubernetes_deployment_v1.adguard, cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "adguard"
}

resource "netbird_nameserver_group" "adguard_devices" {
  name    = "adguard"
  groups  = [netbird_group.devices.id]
  domains = []
  primary = true
  enabled = true
  nameservers = [
    {
      ip      = data.netbird_peer.adguard.ip
      ns_type = "udp"
      port    = 53
    }
  ]
}
