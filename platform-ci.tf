# CI deployer: namespace-scoped credentials for GitHub Actions rollout restarts,
# replaces the cluster-admin kubeconfig in the HESTIA_KUBECONFIG secret.

resource "kubernetes_service_account_v1" "ci_deployer" {
  metadata {
    name      = "ci-deployer"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
}

resource "kubernetes_role_v1" "ci_deployer" {
  metadata {
    name      = "ci-deployer"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "ci_deployer" {
  metadata {
    name      = "ci-deployer"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ci_deployer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ci_deployer.metadata[0].name
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }
}

resource "kubernetes_secret_v1" "ci_deployer_token" {
  metadata {
    name      = "ci-deployer-token"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.ci_deployer.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

output "ci_kubeconfig" {
  description = "Namespace-scoped kubeconfig for GitHub Actions (HESTIA_KUBECONFIG secret). Retire once the in-cluster runner is the sole deploy path."
  sensitive   = true
  value = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = var.cluster_name
      cluster = {
        server                     = "https://${var.node_ip}:6443"
        certificate-authority-data = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
      }
    }]
    users = [{
      name = "ci-deployer"
      user = { token = kubernetes_secret_v1.ci_deployer_token.data["token"] }
    }]
    contexts = [{
      name = var.cluster_name
      context = {
        cluster   = var.cluster_name
        user      = "ci-deployer"
        namespace = kubernetes_namespace_v1.websites.metadata[0].name
      }
    }]
    current-context = var.cluster_name
  })
}

# ── In-cluster GitHub Actions runner ──────────────────────────────────────────
# Runs the deploy step of site-deploy.yml on the cluster network, so kubectl
# reaches the API server internally (kubernetes.default.svc) instead of over the
# public 6443 endpoint — the prerequisite for firewalling 6443 down to the mesh.
# The runner pod executes as a ServiceAccount bound to the same narrowly-scoped
# ci-deployer Role, so no kubeconfig is handed to GitHub at all.
#
# Gated on the token: with github_runner_token unset the deployment is not
# created, so merging this is a no-op until the PAT is set in TFC. Only the
# deploy job routes here (runs-on: hestia-incluster); builds stay on
# GitHub-hosted runners, so the pod needs no Docker daemon.

resource "kubernetes_namespace_v1" "ci" {
  metadata {
    name = "ci"
    labels = {
      # runner image starts its entrypoint as root then drops to the runner
      # user, so baseline (not restricted) is the tightest PSS that still runs it
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

resource "kubernetes_service_account_v1" "github_runner" {
  metadata {
    name      = "github-runner"
    namespace = kubernetes_namespace_v1.ci.metadata[0].name
  }
}

# reuse the existing ci-deployer Role (websites ns: apps/deployments
# get/list/watch/patch) — no new permission surface, just a second subject
resource "kubernetes_role_binding_v1" "github_runner_deployer" {
  metadata {
    name      = "github-runner-deployer"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.ci_deployer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.github_runner.metadata[0].name
    namespace = kubernetes_namespace_v1.ci.metadata[0].name
  }
}

resource "kubernetes_secret_v1" "github_runner_token" {
  metadata {
    name      = "github-runner-token"
    namespace = kubernetes_namespace_v1.ci.metadata[0].name
  }
  data = {
    access-token = var.github_runner_token
  }
}

resource "kubernetes_deployment_v1" "github_runner" {
  count = var.github_runner_token != "" ? 1 : 0

  metadata {
    name      = "github-runner"
    namespace = kubernetes_namespace_v1.ci.metadata[0].name
    labels    = { app = "github-runner" }
  }

  spec {
    replicas = var.github_runner_replicas

    selector {
      match_labels = { app = "github-runner" }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = { app = "github-runner" }
      }

      spec {
        enable_service_links = false
        service_account_name = kubernetes_service_account_v1.github_runner.metadata[0].name

        container {
          name = "runner"
          # verify this tag resolves before first enable; Renovate/TF reconcile it after
          image = "myoung34/github-runner:2.335.1-ubuntu-jammy"

          env {
            name  = "REPO_URL"
            value = "https://github.com/Vinnelle/hestia"
          }
          env {
            name  = "RUNNER_SCOPE"
            value = "repo"
          }
          env {
            name  = "LABELS"
            value = "hestia-incluster"
          }
          env {
            name  = "RUNNER_NAME_PREFIX"
            value = "hestia-incluster"
          }
          # pinned image owns the binary version; don't let the runner self-update
          env {
            name  = "DISABLE_AUTO_UPDATE"
            value = "true"
          }
          env {
            name = "ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.github_runner_token.metadata[0].name
                key  = "access-token"
              }
            }
          }

          security_context {
            allow_privilege_escalation = false
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }
}
