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

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.15.1"
  namespace  = kubernetes_namespace_v1.platform.metadata[0].name

  values = [
    file("${path.module}/../helm-values/ingress-nginx/values.yaml")
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.2"
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
