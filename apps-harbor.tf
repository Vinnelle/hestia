
resource "kubernetes_namespace_v1" "harbor" {
  metadata {
    name = "harbor"
  }
}

resource "cloudflare_dns_record" "registry_admin_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "registry.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

resource "helm_release" "harbor" {
  name       = "harbor"
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = "1.19.1"
  namespace  = kubernetes_namespace_v1.harbor.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/harbor/values.yaml.tftpl", {
      admin_password = var.harbor_admin_password
      cluster_issuer = local.vinnel_cloud_cluster_issuer
    })
  ]
}

resource "harbor_project" "vin_moe" {
  depends_on = [helm_release.harbor]
  name       = "vin-moe"
}

resource "harbor_project" "monke_academy" {
  depends_on = [helm_release.harbor]
  name       = "monke-academy"
}

resource "harbor_project" "vinnel_cloud" {
  depends_on = [helm_release.harbor]
  name       = "vinnel-cloud"
}

resource "harbor_project" "ci_runner" {
  depends_on = [helm_release.harbor]
  name       = "ci-runner"
}

resource "random_password" "harbor_robot" {
  length  = 24
  special = false
}

resource "harbor_robot_account" "ci" {
  depends_on        = [helm_release.harbor]
  name              = "ci"
  description       = "push/pull for vin-moe, monke-academy, vinnel-cloud site builds"
  level             = "system"
  secret_wo         = random_password.harbor_robot.result
  secret_wo_version = 1

  permissions {
    kind      = "project"
    namespace = "*"
    access {
      action   = "push"
      resource = "repository"
    }
    access {
      action   = "pull"
      resource = "repository"
    }
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig_websites" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.websites.metadata[0].name
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
