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
    ".dockerconfigjson" = local.registry_dockerconfigjson
  }
}

module "vinnel_cloud_site" {
  source = "./modules/static-site"

  depends_on = [kubernetes_deployment_v1.gitlab, helm_release.ingress_nginx, helm_release.cert_manager, kubernetes_secret_v1.cloudflare_api_token, kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud]

  site_slug         = "vinnel-cloud"
  domain            = "vinnel.cloud"
  zone_id           = data.cloudflare_zone.vinnel_cloud.id
  node_ip           = var.node_ip
  cache_description = "cache everything for vinnel.cloud site"

  cluster_issuer         = local.vinnel_cloud_cluster_issuer
  acme_email             = var.acme_email_vinnel_cloud
  cloudflare_secret_name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name

  namespace            = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
  registry_secret_name = kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud.metadata[0].name
  image                = local.images["vinnel-cloud-site"]
  replicas             = 2

  cpu_request    = "250m"
  memory_request = "64Mi"
  cpu_limit      = "500m"
  memory_limit   = "256Mi"

  vpa_update_mode = "Auto"
}
