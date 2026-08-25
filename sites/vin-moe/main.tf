resource "kubernetes_namespace_v1" "vin_moe" {
  metadata {
    name = "vin-moe"
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig_vin_moe" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.vin_moe.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

module "vin_moe_site" {
  source = "../static-site"

  depends_on = [
    kubernetes_secret_v1.registry_dockerconfig_vin_moe,
  ]

  site_slug         = "vin-moe"
  domain            = "vin.moe"
  extra_hosts       = ["blog.vin.moe"]
  zone_id           = var.zone_id
  node_ip           = var.node_ip
  cache_description = "cache everything for vin.moe"

  cluster_issuer         = var.cluster_issuer
  acme_email             = var.acme_email
  cloudflare_secret_name = var.cloudflare_secret_name

  namespace            = kubernetes_namespace_v1.vin_moe.metadata[0].name
  registry_secret_name = kubernetes_secret_v1.registry_dockerconfig_vin_moe.metadata[0].name
  image                = var.images["vin-moe-site"]
  replicas             = 2
  port_name            = "http"

  cpu_request    = "50m"
  memory_request = "16Mi"
  cpu_limit      = "200m"
  memory_limit   = "64Mi"

  vpa_update_mode = "Auto"
}
