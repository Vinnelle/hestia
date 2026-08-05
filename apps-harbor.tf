
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

  depends_on = [helm_release.ingress_nginx]

  name       = "harbor"
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = "1.19.1"
  namespace  = kubernetes_namespace_v1.harbor.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/harbor/values.yaml.tftpl", {
      admin_password = var.harbor_admin_password
    })
  ]
}

resource "kubernetes_ingress_v1" "registry_vinnel_cloud" {
  depends_on = [helm_release.harbor, helm_release.ingress_nginx]
  metadata {
    name      = "registry-vinnel-cloud"
    namespace = kubernetes_namespace_v1.harbor.metadata[0].name
    annotations = merge(local.authelia_forward_auth_annotations, {
      "cert-manager.io/cluster-issuer"              = local.vinnel_cloud_cluster_issuer
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"

      "nginx.ingress.kubernetes.io/configuration-snippet" = <<-EOT
        more_clear_headers "X-Frame-Options";
        more_clear_headers "Content-Security-Policy";
        if ($http_sec_fetch_dest = "document") {
          return 302 https://admin.vinnel.cloud/#registry;
        }
        proxy_set_header Accept-Encoding "";
        sub_filter '</head>' '<script src="${local.admin_frame_js_href["registry"]}"></script><link rel="stylesheet" href="${local.admin_frame_css_href}" /></head>';
        sub_filter_once on;
      EOT

      "nginx.ingress.kubernetes.io/server-snippet" = local.admin_frame_brand_locations["registry"]
    })
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["registry.vinnel.cloud"]
      secret_name = "registry-tls"
    }

    rule {
      host = "registry.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "harbor-portal"
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

resource "kubernetes_ingress_v1" "registry_api_vinnel_cloud" {
  depends_on = [helm_release.harbor, helm_release.ingress_nginx, kubernetes_ingress_v1.registry_vinnel_cloud]
  metadata {
    name      = "registry-api-vinnel-cloud"
    namespace = kubernetes_namespace_v1.harbor.metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size" = "0"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["registry.vinnel.cloud"]
      secret_name = "registry-tls"
    }

    rule {
      host = "registry.vinnel.cloud"
      http {
        dynamic "path" {
          for_each = ["/api/", "/service/", "/v2/", "/c/"]
          content {
            path      = path.value
            path_type = "Prefix"
            backend {
              service {
                name = "harbor-core"
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
}

resource "harbor_project" "vin_moe" {
  depends_on = [helm_release.harbor, kubernetes_ingress_v1.registry_api_vinnel_cloud]
  name       = "vin-moe"
}

resource "harbor_project" "monke_academy" {
  depends_on = [helm_release.harbor, kubernetes_ingress_v1.registry_api_vinnel_cloud]
  name       = "monke-academy"
}

resource "harbor_project" "vinnel_cloud" {
  depends_on = [helm_release.harbor, kubernetes_ingress_v1.registry_api_vinnel_cloud]
  name       = "vinnel-cloud"
}

resource "harbor_project" "ci_runner" {
  depends_on = [helm_release.harbor, kubernetes_ingress_v1.registry_api_vinnel_cloud]
  name       = "ci-runner"
  public     = true
}

resource "random_password" "harbor_robot" {
  length  = 24
  special = false
}

resource "harbor_robot_account" "ci" {
  depends_on        = [helm_release.harbor, kubernetes_ingress_v1.registry_api_vinnel_cloud]
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

resource "random_password" "harbor_oidc_client_secret" {
  length  = 32
  special = false
}

resource "harbor_config_auth" "main" {
  depends_on = [helm_release.harbor, kubernetes_ingress_v1.registry_api_vinnel_cloud]

  auth_mode = "oidc_auth"

  oidc_name                     = "Authelia"
  oidc_endpoint                 = "https://auth.vinnel.cloud"
  oidc_client_id                = "harbor"
  oidc_client_secret_wo         = random_password.harbor_oidc_client_secret.result
  oidc_client_secret_wo_version = 1
  oidc_scope                    = "openid,profile,email"
  oidc_user_claim               = "preferred_username"
  oidc_verify_cert              = true
  oidc_auto_onboard             = true
  primary_auth_mode             = true
}

resource "kubernetes_secret_v1" "registry_dockerconfig_arc_runners" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.arc_runners.metadata[0].name
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
