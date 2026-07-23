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

# Pull auth for the momus image (Harbor project vinnel-cloud) — same robot
# account as the websites, but the secret has to exist in this namespace too.
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
  # group membership is handled by netbird_group.servers.peers instead —
  # see the matching comment in apps-adguard.tf
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
  # Authorized keys for the 'ida' user: parsed from momus/ssh/authorized_keys
  # (one key per line, '#' comments and blank lines dropped), merged with the
  # legacy debian_server_ssh_public_key variable if it's still set. distinct()
  # drops duplicates if a key appears in both.
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

# Cluster-admin kubeconfig, mounted read-only into momus so you can drive the
# cluster over SSH (kubectl/k). SECURITY: this makes momus a crown-jewel — the
# SSH key that opens momus effectively holds cluster-admin. The credential is a
# dedicated ServiceAccount token rather than the Talos client-cert kubeconfig:
# client certs cannot be revoked short of rotating the cluster CA, whereas this
# is killed instantly by deleting the token secret (terraform taint
# kubernetes_secret_v1.momus_admin_token + apply rotates it), and API audit
# logs attribute momus's actions to its own identity. The entrypoint copies it
# to ~ida/.kube/config so kubectl "just works"; mounted at /etc/momus-kube
# (outside ~/Projects) so it can never be swept into a commit.
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
  # In-cluster API endpoint, not the public node IP: momus is a pod, so this
  # resolves via CoreDNS and keeps working if/when public 6443 is firewalled.
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

# SSH stays key-only (PasswordAuthentication no in sshd_config) — these only
# gate local privilege escalation (sudo/su) once you're already in over SSH.
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

  # regenerating host keys makes every known_hosts entry scream MITM
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

  # losing netbird state re-registers the peer under a new mesh IP, breaking
  # the momus_ssh_address output and any saved SSH config
  lifecycle {
    prevent_destroy = true
  }
}

# Persistent workspace at ~ida/Projects so a repo clone and any work survive
# pod restarts (the rest of the momus home is ephemeral).
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


# Persists the vscode-cli tunnel's device-auth registration (via
# --cli-data-dir) so `code tunnel` doesn't need re-authenticating against
# GitHub/Microsoft every time the pod restarts.
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
  # Immutable digest recorded by momus-build.yml (see README bootstrap step 9) —
  # the baked image ships sshd, kubectl, love, starship and the vscode CLI,
  # all checksum-verified at build time.
  momus_image = local.images["momus"]

  momus_config_hash = sha256(join("", [
    file("${path.module}/momus/ssh/sshd_config"),
    file("${path.module}/momus/motd/motd"),
    file("${path.module}/momus/shell/.zshrc"),
    file("${path.module}/momus/shell/starship.toml"),
    # roll the pod when the authorized keys change (file or legacy var), so
    # adding/rotating a key takes effect — the entrypoint only copies
    # authorized_keys to ~/.ssh at start
    local.momus_authorized_keys,
    # roll the pod on password rotation too, so a `terraform taint` of either
    # random_password actually takes effect instead of sitting unused in the secret
    random_password.momus_root.result,
    random_password.momus_ida_sudo.result,
    # and on kubeconfig/token rotation — the entrypoint only copies it to
    # ~ida/.kube/config at start, so a revoke-and-reissue must restart the pod
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
            # sudo is a setuid-root binary; no_new_privs (what
            # allow_privilege_escalation=false sets) blocks setuid gains
            # entirely, so this has to be true for `sudo` inside the container
            # to work at all. Traded deliberately for the sudo requirement.
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

          # The image is now fully baked, but sshd still needs time for secret
          # hydration, PVC ownership fixes, and first-boot host-key generation.
          # Keep startup_probe as the guardrail before readiness/liveness start
          # enforcing the steady-state SSH listener.
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
          image = "netbirdio/netbird:0.74.3"

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
  depends_on = [kubernetes_deployment_v1.momus, netbird_setup_key.momus, cloudflare_dns_record.proxy_vinnel_cloud]
  name       = "momus"
}
