# vin.moe

module "vin_moe" {
  source = "./sites/vin-moe"

  depends_on = [module.platform_core, module.gitlab]

  zone_id                   = module.platform_core.zone_id_vin_moe
  relay_ip                  = module.platform_relay.ipv4
  cluster_issuer            = local.vin_moe_cluster_issuer
  registry_dockerconfigjson = module.gitlab.registry_dockerconfigjson
  images                    = local.images
}

# vinnel.cloud

module "vinnel_cloud" {
  source = "./sites/vinnel-cloud"

  depends_on = [module.platform_core, module.gitlab]

  zone_id                   = module.platform_core.zone_id_vinnel_cloud
  relay_ip                  = module.platform_relay.ipv4
  cluster_issuer            = local.vinnel_cloud_cluster_issuer
  registry_dockerconfigjson = module.gitlab.registry_dockerconfigjson
  images                    = local.images
}
