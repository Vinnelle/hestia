
module "monke_academy_site" {
  source = "./modules/static-site"

  depends_on = [
    helm_release.cert_manager,
    helm_release.ingress_nginx,
    helm_release.harbor,
    harbor_project.monke_academy,
    kubernetes_deployment_v1.gitlab,
    kubernetes_secret_v1.cloudflare_api_token,
    kubernetes_secret_v1.registry_dockerconfig_websites,
  ]

  site_slug         = "monke-academy"
  domain            = "monke.academy"
  zone_id           = data.cloudflare_zone.monke_academy.id
  node_ip           = var.node_ip
  cache_description = "cache everything for monke.academy"

  cluster_issuer         = local.monke_academy_cluster_issuer
  acme_email             = var.acme_email_monke_academy
  cloudflare_secret_name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name

  namespace            = kubernetes_namespace_v1.websites.metadata[0].name
  registry_secret_name = kubernetes_secret_v1.registry_dockerconfig_websites.metadata[0].name
  image                = local.images["monke-academy-site"]
  replicas             = 2

  cpu_request    = "250m"
  memory_request = "64Mi"
  cpu_limit      = "500m"
  memory_limit   = "256Mi"

  vpa_update_mode = "Auto"
}
