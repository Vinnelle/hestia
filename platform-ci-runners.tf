
resource "kubernetes_namespace_v1" "arc_systems" {
  metadata {
    name = "arc-systems"
  }
}

resource "kubernetes_namespace_v1" "arc_runners" {
  metadata {
    name = "arc-runners"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_secret_v1" "arc_github_app" {
  metadata {
    name      = "arc-github-app"
    namespace = kubernetes_namespace_v1.arc_runners.metadata[0].name
  }

  data = {
    github_app_id              = var.gh_app_id
    github_app_installation_id = var.gh_app_installation_id
    github_app_private_key     = var.gh_app_private_key
  }
}

resource "helm_release" "arc_controller" {
  name       = "arc"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = "0.14.2"
  namespace  = kubernetes_namespace_v1.arc_systems.metadata[0].name

  values = [
    file("${path.module}/helm-values/arc-controller/values.yaml")
  ]
}

resource "helm_release" "arc_runner" {
  name       = "arc-runner"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.14.2"
  namespace  = kubernetes_namespace_v1.arc_runners.metadata[0].name

  depends_on = [helm_release.arc_controller]

  values = [
    templatefile("${path.module}/helm-values/arc-runner/values.yaml.tftpl", {
      registry_internal_ip = var.node_ip
    })
  ]
}

resource "kubernetes_network_policy_v1" "arc_runners_egress" {
  depends_on = [helm_release.cilium, helm_release.arc_runner]

  metadata {
    name      = "arc-runners-egress"
    namespace = kubernetes_namespace_v1.arc_runners.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "monitoring"
          }
        }
      }
      ports {
        port     = 8080
        protocol = "TCP"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = { "k8s-app" = "kube-dns" }
        }
      }
      ports {
        port     = 53
        protocol = "UDP"
      }
      ports {
        port     = 53
        protocol = "TCP"
      }
    }

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
          except = [
            "10.244.0.0/16",
            "10.96.0.0/12",
          ]
        }
      }
    }
  }
}
