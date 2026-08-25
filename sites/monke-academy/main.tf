resource "kubernetes_namespace_v1" "monke_academy" {
  metadata {
    name = "monke-academy"
  }
}

resource "kubernetes_secret_v1" "registry_dockerconfig_monke_academy" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = kubernetes_namespace_v1.monke_academy.metadata[0].name
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

module "monke_academy_site" {
  source = "../../modules/static-site"

  depends_on = [
    kubernetes_secret_v1.registry_dockerconfig_monke_academy,
  ]

  site_slug         = "monke-academy"
  domain            = "monke.academy"
  zone_id           = var.zone_id
  node_ip           = var.node_ip
  cache_description = "cache everything for monke.academy"

  cluster_issuer         = var.cluster_issuer
  acme_email             = var.acme_email
  cloudflare_secret_name = var.cloudflare_secret_name

  namespace            = kubernetes_namespace_v1.monke_academy.metadata[0].name
  registry_secret_name = kubernetes_secret_v1.registry_dockerconfig_monke_academy.metadata[0].name
  image                = var.images["monke-academy-site"]
  replicas             = 2

  cpu_request    = "250m"
  memory_request = "64Mi"
  cpu_limit      = "500m"
  memory_limit   = "256Mi"

  vpa_update_mode = "Auto"
}
