# AdGuard

module "adguard" {
  source = "./apps/adguard"

  depends_on = [module.platform_vpa]

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["adguard"]
  devices_group_id                = module.proxy_netbird.devices_group_id
}

# Admin

module "admin" {
  source = "./apps/admin"

  depends_on = [module.platform_core, module.platform_vpa, module.platform_storage, module.gitlab]

  namespace                         = module.vinnel_cloud.namespace
  registry_secret_name              = module.vinnel_cloud.registry_secret_name
  image                             = local.images["vinnel-cloud-admin"]
  zone_id                           = module.platform_core.zone_id_vinnel_cloud
  node_ip                           = var.node_ip
  relay_ip                          = module.platform_relay.ipv4
  relay_address                     = module.platform_relay.relay_address
  relay_metrics_port                = module.platform_relay.metrics_port
  relay_location                    = "Infomaniak ${var.infomaniak_region}"
  cluster_issuer                    = local.vinnel_cloud_cluster_issuer
  ingress_class_name                = module.platform_core.ingress_class_name
  authelia_forward_auth_annotations = local.authelia_forward_auth_annotations
  observability_namespace           = module.observability_grafana.namespace
  games_namespace                   = module.minecraft.namespace
  minecraft_rcon_secret_name        = module.minecraft.rcon_secret_name
  minecraft_dns_record_name         = module.minecraft.dns_record_name
  satisfactory_saves_service_name   = module.satisfactory.saves_service_name
  satisfactory_admin_secret_name    = module.satisfactory.admin_secret_name
  gitlab_project_id                 = module.gitlab.project_id
  gitlab_default_branch             = module.gitlab.default_branch
}

# Automations

module "automations" {
  source = "./apps/automations"

  depends_on = [module.platform_core, module.gitlab]

  image                     = local.images["automations"]
  registry_dockerconfigjson = module.gitlab.registry_dockerconfigjson
  node_ip                   = var.node_ip
  observability_namespace   = module.observability_grafana.namespace
  gitlab_project_id         = module.gitlab.project_id
  renovate_author_id        = module.gitlab.ci_bot_user_id
  llm_base_url              = module.llm.base_url
  llm_model                 = module.llm.model
  llm_api_key               = module.llm.api_key
}

# GitLab

module "gitlab" {
  source = "./apps/gitlab"

  depends_on = [module.platform_core, module.platform_vpa]

  zone_id                  = module.platform_core.zone_id_vinnel_cloud
  node_ip                  = var.node_ip
  relay_ip                 = module.platform_relay.ipv4
  sops_age_key             = var.gitlab_ci_age_key
  cluster_issuer           = local.vinnel_cloud_cluster_issuer
  ingress_class_name       = module.platform_core.ingress_class_name
  acme_email_vin_moe       = var.acme_email_vin_moe
  resend_api_key           = var.resend_api_key
  gitlab_mirror_github_pat = var.gitlab_mirror_github_pat
  gitlab_tfc_api_token     = var.gitlab_tfc_api_token
  docker_hub_username      = var.docker_hub_username
  docker_hub_access_token  = var.docker_hub_access_token
  ci_kubeconfig            = module.platform_ci.ci_kubeconfig
  seaweedfs_s3_access_key  = module.seaweedfs.s3_access_key
  seaweedfs_s3_secret_key  = module.seaweedfs.s3_secret_key
}

# LLM

module "llm" {
  source = "./apps/llm"

  depends_on = [module.platform_storage]

  runtime_class_name = module.platform_gpu.runtime_class_name
}

# Mail

module "mail" {
  source = "./apps/mail"

  zone_id = module.platform_core.zone_id_vinnel_cloud
}

# Matrix

module "matrix" {
  source = "./apps/matrix"

  depends_on = [module.platform_vpa]

  zone_id            = module.platform_core.zone_id_vinnel_cloud
  relay_ip           = module.platform_relay.ipv4
  cluster_issuer     = local.vinnel_cloud_cluster_issuer
  ingress_class_name = module.platform_core.ingress_class_name
  server_name        = "vinnel.cloud"
  hostname           = "matrix.vinnel.cloud"
}

# Miniflux

module "miniflux" {
  source = "./apps/miniflux"

  depends_on = [module.platform_vpa]

  zone_id            = module.platform_core.zone_id_vinnel_cloud
  relay_ip           = module.platform_relay.ipv4
  cluster_issuer     = local.vinnel_cloud_cluster_issuer
  ingress_class_name = module.platform_core.ingress_class_name
}

# Nextcloud

module "nextcloud" {
  source = "./apps/nextcloud"

  depends_on = [module.platform_core, module.platform_vpa]

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["cloud"]
  import_s3_endpoint              = module.platform_backup.s3_endpoint
  import_s3_bucket                = module.platform_backup.import_bucket
  import_s3_access_key            = var.mega_import_access_key
  import_s3_secret_key            = var.mega_import_secret_key
  seaweedfs_s3_access_key         = module.seaweedfs.s3_access_key
  seaweedfs_s3_secret_key         = module.seaweedfs.s3_secret_key
}

# Registry Cache

module "registry_cache" {
  source = "./apps/registry-cache"

  depends_on = [module.platform_vpa]

  zone_id                 = module.platform_core.zone_id_vinnel_cloud
  relay_ip                = module.platform_relay.ipv4
  cluster_issuer          = local.vinnel_cloud_cluster_issuer
  ingress_class_name      = module.platform_core.ingress_class_name
  docker_hub_username     = var.docker_hub_username
  docker_hub_access_token = var.docker_hub_access_token
  gitlab_project_id       = module.gitlab.project_id
}

# SearXNG

module "searxng" {
  source = "./apps/searxng"

  depends_on = [module.platform_core, module.platform_vpa]

  zone_id                           = module.platform_core.zone_id_vinnel_cloud
  relay_ip                          = module.platform_relay.ipv4
  cluster_issuer                    = local.vinnel_cloud_cluster_issuer
  authelia_forward_auth_annotations = local.authelia_forward_auth_annotations
}

# SeaweedFS

module "seaweedfs" {
  source = "./apps/seaweedfs"

  depends_on = [module.platform_core, module.platform_vpa]

  namespace                       = module.platform_storage.namespace
  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  admin_frame_service_annotations = local.admin_framed_service_annotations["seaweed"]
}

# Shell

module "shell" {
  source = "./apps/shell"

  depends_on = [module.platform_core, module.platform_vpa, module.gitlab]

  namespace                       = module.vinnel_cloud.namespace
  registry_secret_name            = module.vinnel_cloud.registry_secret_name
  image                           = local.images["vinnel-cloud-shell"]
  admin_service_account_name      = module.admin.service_account_name
  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["shell"]
}
