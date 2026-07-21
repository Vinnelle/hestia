resource "kubernetes_namespace_v1" "websites" {
  metadata {
    name = "websites"
  }
}

resource "kubernetes_namespace_v1" "services" {
  metadata {
    name = "services"
  }
}

resource "kubernetes_namespace_v1" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
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
  namespace  = kubernetes_namespace_v1.ingress_nginx.metadata[0].name

  values = [
    file("${path.module}/helm-values/ingress-nginx/values.yaml")
  ]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.0"
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

data "cloudflare_zone" "monke_academy" {
  filter = { name = "monke.academy" }
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

resource "cloudflare_zone_setting" "monke_academy_ssl" {
  zone_id    = data.cloudflare_zone.monke_academy.id
  setting_id = "ssl"
  value      = "strict"
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
