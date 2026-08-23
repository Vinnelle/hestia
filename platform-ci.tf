resource "kubernetes_service_account_v1" "ci_deployer" {
  metadata {
    name      = "ci-deployer"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
  }
}

resource "kubernetes_cluster_role_v1" "ci_deployer" {
  metadata {
    name = "ci-deployer"
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "ci_deployer" {
  for_each = local.ci_deploy_namespaces

  metadata {
    name      = "ci-deployer"
    namespace = each.value
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.ci_deployer.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.ci_deployer.metadata[0].name
    namespace = kubernetes_service_account_v1.ci_deployer.metadata[0].namespace
  }
}

resource "kubernetes_secret_v1" "ci_deployer_token" {
  metadata {
    name      = "ci-deployer-token"
    namespace = kubernetes_namespace_v1.forge.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account_v1.ci_deployer.metadata[0].name
    }
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

locals {
  ci_deploy_namespaces = toset([
    kubernetes_namespace_v1.vin_moe.metadata[0].name,
    kubernetes_namespace_v1.monke_academy.metadata[0].name,
    kubernetes_namespace_v1.vinnel_cloud.metadata[0].name,
  ])
}

locals {
  ci_kubeconfig = yamlencode({
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
        namespace = kubernetes_namespace_v1.forge.metadata[0].name
      }
    }]
    current-context = var.cluster_name
  })
}

output "ci_kubeconfig" {
  description = "Namespace-scoped kubeconfig for GitHub Actions (KUBECONFIG secret)."
  sensitive   = true
  value       = local.ci_kubeconfig
}
