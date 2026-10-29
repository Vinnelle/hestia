resource "kubernetes_namespace_v1" "platform" {
  metadata {
    name = "platform"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

data "kubernetes_secret_v1" "registry_pull" {
  metadata {
    name      = var.registry_pull_secret.name
    namespace = var.registry_pull_secret.namespace
  }
}

resource "kubernetes_secret_v1" "registry_pull" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.platform.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = try(data.kubernetes_secret_v1.registry_pull.data[".dockerconfigjson"], jsonencode({ auths = {} }))
  }
}

locals {
  ingress_nginx_image = regex("^(?P<registry>[^/]+)/(?P<image>[^:@]+):(?P<tag>[^@]+)@(?P<digest>sha256:[0-9a-f]{64})$", var.ingress_nginx_image)
}

resource "kubernetes_job_v1" "ingress_nginx_pull" {
  metadata {
    name      = "ingress-nginx-pull-${substr(sha256(var.ingress_nginx_image), 0, 12)}"
    namespace = kubernetes_namespace_v1.platform.metadata[0].name
  }

  spec {
    backoff_limit = 2

    template {
      metadata {}
      spec {
        restart_policy                  = "Never"
        automount_service_account_token = false

        image_pull_secrets {
          name = kubernetes_secret_v1.registry_pull.metadata[0].name
        }

        security_context {
          run_as_non_root = true
          run_as_user     = 101
          run_as_group    = 82
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name    = "pull"
          image   = var.ingress_nginx_image
          command = ["/bin/true"]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "16Mi"
            }
            limits = {
              memory = "16Mi"
            }
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "10m"
    update = "10m"
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.15.1"
  namespace  = kubernetes_namespace_v1.platform.metadata[0].name

  values = [
    file("${path.module}/../helm-values/ingress-nginx/values.yaml")
  ]

  set = [
    {
      name  = "controller.image.registry"
      value = local.ingress_nginx_image.registry
    },
    {
      name  = "controller.image.image"
      value = local.ingress_nginx_image.image
    },
    {
      name  = "controller.image.tag"
      value = local.ingress_nginx_image.tag
      type  = "string"
    },
    {
      name  = "controller.image.digest"
      value = local.ingress_nginx_image.digest
    },
    {
      name  = "imagePullSecrets[0].name"
      value = kubernetes_secret_v1.registry_pull.metadata[0].name
    },
  ]

  depends_on = [kubernetes_job_v1.ingress_nginx_pull]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.3"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "extraArgs[0]"
      value = "--dns01-recursive-nameservers=1.1.1.1:53\\,8.8.8.8:53"
      type  = "string"
    },
    {
      name  = "extraArgs[1]"
      value = "--dns01-recursive-nameservers-only"
    },
    {
      name  = "resources.requests.memory"
      value = "96Mi"
    },
    {
      name  = "resources.limits.memory"
      value = "512Mi"
    },
    {
      name  = "cainjector.resources.requests.memory"
      value = "64Mi"
    },
    {
      name  = "cainjector.resources.limits.memory"
      value = "384Mi"
    },
    {
      name  = "webhook.resources.requests.memory"
      value = "64Mi"
    },
    {
      name  = "webhook.resources.limits.memory"
      value = "256Mi"
    }
  ]
}

data "cloudflare_zone" "vin_moe" {
  filter = { name = "vin.moe" }
}

data "cloudflare_zone" "vinnel_cloud" {
  filter = { name = "vinnel.cloud" }
}

resource "cloudflare_zone_setting" "vin_moe_ssl" {
  zone_id    = data.cloudflare_zone.vin_moe.id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "vinnel_cloud_ssl" {
  zone_id    = data.cloudflare_zone.vinnel_cloud.id
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_universal_ssl_setting" "vin_moe" {
  zone_id = data.cloudflare_zone.vin_moe.id
  enabled = false
}

resource "cloudflare_universal_ssl_setting" "vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  enabled = false
}

resource "cloudflare_dns_record" "vin_moe_caa" {
  zone_id = data.cloudflare_zone.vin_moe.id
  name    = "vin.moe"
  type    = "CAA"
  ttl     = 1
  data = {
    flags = 0
    tag   = "issue"
    value = "letsencrypt.org; validationmethods=dns-01"
  }
}

resource "cloudflare_dns_record" "vinnel_cloud_caa" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "vinnel.cloud"
  type    = "CAA"
  ttl     = 1
  data = {
    flags = 0
    tag   = "issue"
    value = "letsencrypt.org; validationmethods=dns-01"
  }
}

resource "kubernetes_secret_v1" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
  }
  data = {
    api-token = var.cloudflare_api_token
  }
  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "cluster_issuer" {
  for_each = var.cluster_issuers

  yaml_body = templatefile("${path.module}/cluster-issuer.yaml.tftpl", {
    issuer_name            = each.key
    email                  = each.value
    cloudflare_secret_name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name
  })
}
