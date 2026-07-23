
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
  adguard_ordinals = toset(["0", "1"])

  adguard_config_template_yaml = yamlencode({
    schema_version = 29
    http = {
      address = "0.0.0.0:3000"
    }
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
  for_each       = local.adguard_ordinals
  depends_on     = [cloudflare_dns_record.proxy_vinnel_cloud]
  name           = "adguard-${each.key}"
  type           = "one-off"
  expiry_seconds = 3600
  ephemeral      = false
  usage_limit    = 1
  auto_groups    = [netbird_group.adguard.id]
}

resource "kubernetes_secret_v1" "adguard_netbird_setup_keys" {
  metadata {
    name      = "adguard-netbird-setup-keys"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  data = {
    for ordinal, key in netbird_setup_key.adguard : "setup-key-${ordinal}" => key.key
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

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_service_v1" "adguard_headless" {
  metadata {
    name      = "adguard-headless"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  spec {
    cluster_ip = "None"
    selector = {
      app = "adguard"
    }
    port {
      port        = 3000
      target_port = "http"
    }
  }
}

resource "kubernetes_stateful_set_v1" "adguard" {
  metadata {
    name      = "adguard"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
    labels = {
      app = "adguard"
    }
  }

  spec {
    replicas     = 2
    service_name = kubernetes_service_v1.adguard_headless.metadata[0].name

    selector {
      match_labels = {
        app = "adguard"
      }
    }

    persistent_volume_claim_retention_policy {
      when_deleted = "Retain"
      when_scaled  = "Retain"
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
          image = "netbirdio/netbird:0.74.7"

          command = ["sh", "-c"]
          args = [<<-EOT
            hostname=$(cat /etc/hostname)
            ordinal=$${hostname##*-}
            export NB_SETUP_KEY=$(cat "/secrets/setup-key-$${ordinal}")
            exec /usr/local/bin/netbird-entrypoint.sh
          EOT
          ]

          env {
            name  = "NB_MANAGEMENT_URL"
            value = "https://proxy.vinnel.cloud"
          }

          env {
            name  = "NB_DISABLE_DNS"
            value = "true"
          }

          security_context {
            capabilities {
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

          volume_mount {
            name       = "netbird-setup-keys"
            mount_path = "/secrets"
            read_only  = true
          }
        }

        volume {
          name = "template"
          config_map {
            name = kubernetes_config_map_v1.adguard_config_template.metadata[0].name
          }
        }

        volume {
          name = "netbird-setup-keys"
          secret {
            secret_name = kubernetes_secret_v1.adguard_netbird_setup_keys.metadata[0].name
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

    volume_claim_template {
      metadata {
        name = "conf"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "256Mi"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "work"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "2Gi"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "netbird-state"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "64Mi"
          }
        }
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "adguard" {
  metadata {
    name      = "adguard"
    namespace = kubernetes_namespace_v1.adguard.metadata[0].name
  }
  spec {
    min_available = 1
    selector {
      match_labels = {
        app = "adguard"
      }
    }
  }
}

resource "kubectl_manifest" "adguard_vpa" {
  depends_on = [helm_release.vpa, kubernetes_stateful_set_v1.adguard]
  yaml_body = templatefile("${path.module}/manifests/vpa/vpa.yaml.tftpl", {
    name        = "adguard"
    namespace   = kubernetes_namespace_v1.adguard.metadata[0].name
    target_kind = "StatefulSet"
    target_name = kubernetes_stateful_set_v1.adguard.metadata[0].name
    update_mode = "Initial"
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
  for_each   = local.adguard_ordinals
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "adguard-${each.key}"
}

resource "netbird_nameserver_group" "adguard_devices" {
  name    = "adguard"
  groups  = [netbird_group.devices.id]
  domains = []
  primary = true
  enabled = true
  nameservers = [
    for ordinal in sort(keys(data.netbird_peer.adguard)) : {
      ip      = data.netbird_peer.adguard[ordinal].ip
      ns_type = "udp"
      port    = 53
    }
  ]
}
