resource "kubernetes_namespace_v1" "vinnel_cloud" {
  metadata {
    name = "vinnel-cloud"
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig_vinnel_cloud" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

module "vinnel_cloud_site" {
  source = "../static-site"

  depends_on = [
    kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud,
  ]

  site_slug         = "vinnel-cloud"
  domain            = "vinnel.cloud"
  zone_id           = var.zone_id
  node_ip           = var.node_ip
  cache_description = "cache everything for vinnel.cloud site"

  cluster_issuer         = var.cluster_issuer
  acme_email             = var.acme_email
  cloudflare_secret_name = var.cloudflare_secret_name

  namespace            = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  registry_secret_name = kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud.metadata[0].name
  image                = var.images["vinnel-cloud-site"]
  replicas             = 2

  cpu_request    = "250m"
  memory_request = "64Mi"
  cpu_limit      = "500m"
  memory_limit   = "256Mi"

  vpa_update_mode = "Auto"
}
