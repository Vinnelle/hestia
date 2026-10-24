# Minecraft

module "minecraft" {
  source = "./games/minecraft"

  depends_on = [module.platform_vpa]

  zone_id                   = module.platform_core.zone_id_vin_moe
  relay_ip                  = module.platform_relay.ipv4
  dashboard_namespace       = module.vinnel_cloud.namespace
  minecraft_modpack_zip_url = var.minecraft_modpack_zip_url
  curseforge_api_key        = var.curseforge_api_key
}

# Satisfactory

module "satisfactory" {
  source = "./games/satisfactory"

  depends_on = [module.platform_vpa]

  namespace                   = module.minecraft.namespace
  zone_id                     = module.platform_core.zone_id_vin_moe
  relay_ip                    = module.platform_relay.ipv4
  dashboard_namespace         = module.vinnel_cloud.namespace
  satisfactory_admin_password = var.satisfactory_admin_password
}

# Sleeper

module "game_sleeper" {
  source = "./games/sleeper"

  depends_on = [module.minecraft, module.satisfactory]

  namespace                   = module.minecraft.namespace
  image                       = local.images["vinnel-cloud-admin"]
  registry_dockerconfigjson   = module.gitlab.registry_dockerconfigjson
  node_ip                     = var.node_ip
  satisfactory_admin_password = var.satisfactory_admin_password
  observability_namespace     = module.observability_grafana.namespace
}
