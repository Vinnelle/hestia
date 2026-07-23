resource "kubernetes_namespace_v1" "arc_systems" {
  metadata {
    name = "arc-systems"
  }
}

resource "kubernetes_namespace_v1" "arc_runners" {
  metadata {
    name = "arc-runners"
    # dind containerMode needs privileged pods; baseline PSA (namespace default) blocks it.
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

resource "helm_release" "arc_runner_gaia" {
  name       = "arc-runner-gaia"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = "0.14.2"
  namespace  = kubernetes_namespace_v1.arc_runners.metadata[0].name

  depends_on = [helm_release.arc_controller]

  values = [
    templatefile("${path.module}/helm-values/arc-runner-gaia/values.yaml.tftpl", {
      ingress_nginx_cluster_ip = data.kubernetes_service_v1.ingress_nginx_controller.spec[0].cluster_ip
    })
  ]
}

# registry.vinnel.cloud stays Cloudflare-proxied (WAF/DDoS for public
# traffic), but that proxy caps request bodies (100MB on Free/Pro) and
# 413s large docker pushes. Runner pods route around it via hostAliases
# in the runner values template instead, straight to this Service.
data "kubernetes_service_v1" "ingress_nginx_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.ingress_nginx]
}
