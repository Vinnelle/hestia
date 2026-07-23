
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
  description = "Namespace-scoped kubeconfig for GitHub Actions (HESTIA_KUBECONFIG secret)."
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
