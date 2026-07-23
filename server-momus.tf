resource "kubernetes_namespace_v1" "server" {
  metadata {
    name = "server"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig_server" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "registry.vinnel.cloud" = {
          username = harbor_robot_account.ci.full_name
          password = random_password.harbor_robot.result
          auth     = base64encode("${harbor_robot_account.ci.full_name}:${random_password.harbor_robot.result}")
        }
      }
    })
  }
}

resource "netbird_setup_key" "momus" {
  depends_on     = [cloudflare_dns_record.proxy_vinnel_cloud]
  name           = "momus"
  type           = "one-off"
  expiry_seconds = 3600
  ephemeral      = false
  usage_limit    = 1
  auto_groups    = [netbird_group.servers.id]
}

resource "kubernetes_secret_v1" "momus_netbird_setup_key" {
  metadata {
    name      = "momus-netbird-setup-key"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  data = {
    setup-key = netbird_setup_key.momus.key
  }
}

locals {
  momus_authorized_keys = join("\n", distinct(concat(
    [
      for line in split("\n", file("${path.module}/momus/ssh/authorized_keys")) :
      trimspace(line)
      if trimspace(line) != "" && !startswith(trimspace(line), "#")
    ],
    var.debian_server_ssh_public_key != "" ? [trimspace(var.debian_server_ssh_public_key)] : [],
  )))
}

resource "kubernetes_secret_v1" "momus_authorized_keys" {
  metadata {
    name      = "momus-authorized-keys"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  data = {
    authorized_keys = local.momus_authorized_keys
  }
}

resource "kubernetes_service_account_v1" "momus_admin" {
  metadata {
    name      = "momus-admin"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
}

resource "kubernetes_cluster_role_binding_v1" "momus_admin" {
  metadata {
    name = "momus-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.momus_admin.metadata[0].name
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
}

resource "kubernetes_secret_v1" "momus_admin_token" {
  metadata {
    name      = "momus-admin-token"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.momus_admin.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

locals {
  momus_kubeconfig = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.cluster_name
      cluster = {
        server                     = "https://kubernetes.default.svc"
        certificate-authority-data = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
      }
    }]
    users = [{
      name = "momus-admin"
      user = { token = kubernetes_secret_v1.momus_admin_token.data["token"] }
    }]
    contexts = [{
      name = var.cluster_name
      context = {
        cluster = var.cluster_name
        user    = "momus-admin"
      }
    }]
    current-context = var.cluster_name
  })
}

resource "random_password" "momus_root" {
  length  = 32
  special = false
}

resource "random_password" "momus_ida_sudo" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "momus_passwords" {
  metadata {
    name      = "momus-passwords"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  data = {
    root = random_password.momus_root.result
    ida  = random_password.momus_ida_sudo.result
  }
}

resource "kubernetes_secret_v1" "momus_kubeconfig" {
  metadata {
    name      = "momus-kubeconfig"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  data = {
    config = local.momus_kubeconfig
  }
}

resource "kubernetes_config_map_v1" "momus_sshd_config" {
  metadata {
    name      = "momus-sshd-config"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  data = {
    "sshd_config" = file("${path.module}/momus/ssh/sshd_config")
  }
}

resource "kubernetes_config_map_v1" "momus_motd" {
  metadata {
    name      = "momus-motd"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  data = {
    "motd" = file("${path.module}/momus/motd/motd")
  }
}

resource "kubernetes_config_map_v1" "server_dotfiles" {
  metadata {
    name      = "server-dotfiles"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  data = {
    ".zshrc"        = file("${path.module}/momus/shell/.zshrc")
    "starship.toml" = file("${path.module}/momus/shell/starship.toml")
  }
}

resource "kubernetes_persistent_volume_claim_v1" "momus_host_keys" {
  metadata {
    name      = "momus-host-keys-pvc"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "16Mi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_persistent_volume_claim_v1" "momus_netbird_state" {
  metadata {
    name      = "momus-netbird-state-pvc"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
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

resource "kubernetes_persistent_volume_claim_v1" "momus_projects" {
  metadata {
    name      = "momus-projects-pvc"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
  wait_until_bound = false

  lifecycle {
    prevent_destroy = true
  }
}


resource "kubernetes_persistent_volume_claim_v1" "momus_vscode_state" {
  metadata {
    name      = "momus-vscode-state-pvc"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
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

locals {
  momus_image = local.images["momus"]

  momus_config_hash = sha256(join("", [
    file("${path.module}/momus/ssh/sshd_config"),
    file("${path.module}/momus/motd/motd"),
    file("${path.module}/momus/shell/.zshrc"),
    file("${path.module}/momus/shell/starship.toml"),
    local.momus_authorized_keys,
    random_password.momus_root.result,
    random_password.momus_ida_sudo.result,
    local.momus_kubeconfig,
  ]))
}

resource "kubernetes_deployment_v1" "momus" {
  depends_on = [helm_release.harbor, harbor_project.vinnel_cloud, kubernetes_secret_v1.registry_dockerconfig_server]

  metadata {
    name      = "momus"
    namespace = kubernetes_namespace_v1.server.metadata[0].name
    labels = {
      app = "momus"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "momus"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          app = "momus"
        }
        annotations = {
          "config-hash" = local.momus_config_hash
        }
      }

      spec {
        enable_service_links = false
        hostname             = "momus"

        image_pull_secrets {
          name = kubernetes_secret_v1.registry_dockerconfig_server.metadata[0].name
        }

        container {
          name  = "sshd"
          image = local.momus_image

          port {
            name           = "ssh"
            container_port = 2222
          }

          security_context {
            allow_privilege_escalation = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "96Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "sshd-config"
            mount_path = "/etc/ssh/sshd_config"
            sub_path   = "sshd_config"
            read_only  = true
          }

          volume_mount {
            name       = "authorized-keys"
            mount_path = "/run/authorized-keys"
            read_only  = true
          }

          volume_mount {
            name       = "host-keys"
            mount_path = "/etc/ssh/host_keys"
          }

          volume_mount {
            name       = "motd"
            mount_path = "/etc/motd"
            sub_path   = "motd"
            read_only  = true
          }

          volume_mount {
            name       = "dotfiles"
            mount_path = "/run/dotfiles"
            read_only  = true
          }

          volume_mount {
            name       = "kubeconfig"
            mount_path = "/etc/momus-kube"
            read_only  = true
          }

          volume_mount {
            name       = "projects"
            mount_path = "/home/ida/Projects"
          }

          volume_mount {
            name       = "passwords"
            mount_path = "/run/passwords"
            read_only  = true
          }

          volume_mount {
            name       = "vscode-state"
            mount_path = "/home/ida/.vscode-cli"
          }

          startup_probe {
            tcp_socket {
              port = "ssh"
            }
            period_seconds    = 5
            failure_threshold = 40
            timeout_seconds   = 5
          }

          readiness_probe {
            tcp_socket {
              port = "ssh"
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          liveness_probe {
            tcp_socket {
              port = "ssh"
            }
            period_seconds  = 30
            timeout_seconds = 5
          }
        }

        container {
          name  = "netbird"
          image = "netbirdio/netbird:0.74.7"

          env {
            name = "NB_SETUP_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.momus_netbird_setup_key.metadata[0].name
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
            value = "momus"
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
        }

        volume {
          name = "sshd-config"
          config_map {
            name = kubernetes_config_map_v1.momus_sshd_config.metadata[0].name
          }
        }

        volume {
          name = "authorized-keys"
          secret {
            secret_name = kubernetes_secret_v1.momus_authorized_keys.metadata[0].name
          }
        }

        volume {
          name = "host-keys"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.momus_host_keys.metadata[0].name
          }
        }

        volume {
          name = "motd"
          config_map {
            name = kubernetes_config_map_v1.momus_motd.metadata[0].name
          }
        }

        volume {
          name = "dotfiles"
          config_map {
            name = kubernetes_config_map_v1.server_dotfiles.metadata[0].name
          }
        }

        volume {
          name = "kubeconfig"
          secret {
            secret_name = kubernetes_secret_v1.momus_kubeconfig.metadata[0].name
          }
        }

        volume {
          name = "projects"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.momus_projects.metadata[0].name
          }
        }

        volume {
          name = "netbird-state"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.momus_netbird_state.metadata[0].name
          }
        }

        volume {
          name = "passwords"
          secret {
            secret_name = kubernetes_secret_v1.momus_passwords.metadata[0].name
          }
        }

        volume {
          name = "vscode-state"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.momus_vscode_state.metadata[0].name
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

data "netbird_peer" "momus" {
  depends_on = [cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "momus"
}
