# Authelia

module "identity_authelia" {
  source = "./identity/authelia"

  depends_on = [module.platform_vpa]

  zone_id                           = module.platform_core.zone_id_vinnel_cloud
  relay_ip                          = module.platform_relay.ipv4
  cluster_issuer                    = local.vinnel_cloud_cluster_issuer
  ingress_class_name                = module.platform_core.ingress_class_name
  resend_api_key                    = var.resend_api_key
  nextcloud_oidc_client_secret_hash = module.nextcloud.oidc_client_secret_hash
  grafana_oidc_client_secret_hash   = module.observability_grafana.oidc_client_secret_hash
}

# Auth Portal

module "identity_auth_portal" {
  source = "./identity/auth-portal"

  depends_on = [module.platform_vpa, module.gitlab]

  namespace            = module.vinnel_cloud.namespace
  registry_secret_name = module.vinnel_cloud.registry_secret_name
  image                = local.images["vinnel-cloud-auth"]
  ingress_class_name   = module.platform_core.ingress_class_name
}
