# Platform

## Core

module "platform_core" {
  source = "./platform/core"

  cloudflare_api_token = var.cloudflare_api_token
  cluster_issuers = {
    (local.vin_moe_cluster_issuer)      = var.acme_email_vin_moe
    (local.vinnel_cloud_cluster_issuer) = var.acme_email_vinnel_cloud
  }
}

## Relay

module "platform_relay" {
  source = "./platform/relay"

  forwards = local.relay_forwards
}

## Proxmox

module "platform_proxmox" {
  source = "./platform/proxmox"

  node_name        = var.proxmox_node
  lan_cidr         = var.lan_cidr
  talos_iso_url    = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/${local.talos_version}/metal-amd64-secureboot.iso"
  talos_version    = local.talos_version
  talos_iso_sha256 = local.talos_iso_sha256
  pbs_username     = var.pbs_username
  pbs_password     = var.pbs_password
  pbs_fingerprint  = var.pbs_fingerprint

  pbs_encryption_key = var.pbs_encryption_key
}

## VPA

module "platform_vpa" {
  source = "./platform/vpa"

  platform_namespace      = module.platform_core.namespace
  observability_namespace = module.observability_grafana.namespace
}

## CNI

module "platform_cni" {
  source = "./platform/cni"

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["hubble"]
}

## Storage

module "platform_storage" {
  source = "./platform/storage"
}

## Backup

module "platform_backup" {
  source = "./platform/backup"

  providers = {
    aws.mega_s4 = aws.mega_s4
  }

  mega_s4_endpoint_domain = var.mega_s4_endpoint_domain
}

## CI

module "platform_ci" {
  source = "./platform/ci"

  forge_namespace = module.gitlab.namespace
  deploy_namespaces = toset([
    module.vin_moe.namespace,
    module.vinnel_cloud.namespace,
  ])
  cluster_name           = var.cluster_name
  node_ip                = var.node_ip
  cluster_ca_certificate = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
}

## Trivy

module "platform_trivy" {
  source = "./platform/trivy"

  depends_on = [module.platform_vpa, module.observability_grafana]

  namespace = module.platform_core.namespace
}

## Chaos Mesh

module "platform_chaos_mesh" {
  source = "./platform/chaos-mesh"

  namespace = module.platform_core.namespace
  site_namespaces = sort(tolist(toset([
    module.vin_moe.namespace,
    module.vinnel_cloud.namespace,
  ])))
}

## Job Reaper

module "platform_job_reaper" {
  source = "./platform/job-reaper"

  namespace = module.platform_core.namespace
}

## Terraform Mirror

module "platform_terraform_mirror" {
  source = "./platform/terraform-mirror"

  region            = var.linode_region
  gitlab_project_id = module.gitlab.project_id
}

## Network Policy

module "platform_network_policy" {
  source = "./platform/network-policy"

  depends_on = [
    module.platform_cni,
    module.identity_authelia,
    module.adguard,
    module.nextcloud,
    module.gitlab,
    module.matrix,
    module.miniflux,
    module.proxy_netbird,
    module.registry_cache,
    module.searxng,
    module.platform_storage,
    module.vin_moe,
    module.vinnel_cloud,
  ]

  telemetry_namespace = module.observability_grafana.namespace
  relay_address       = module.platform_relay.relay_address
}

# Identity

## Authelia

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

## Auth Portal

module "identity_auth_portal" {
  source = "./identity/auth-portal"

  depends_on = [module.platform_vpa, module.gitlab]

  namespace            = module.vinnel_cloud.namespace
  registry_secret_name = module.vinnel_cloud.registry_secret_name
  image                = local.images["vinnel-cloud-auth"]
  ingress_class_name   = module.platform_core.ingress_class_name
}

# Observability

## Grafana

module "observability_grafana" {
  source = "./observability/grafana"

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  node_ip                         = var.node_ip
  cluster_name                    = var.cluster_name
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["grafana"]
  alert_email                     = var.alert_email
  resend_api_key                  = var.resend_api_key
}

## Better Stack

module "observability_betterstack" {
  source = "./observability/betterstack"

  namespace          = module.vinnel_cloud.namespace
  zone_id            = module.platform_core.zone_id_vinnel_cloud
  relay_ip           = module.platform_relay.ipv4
  cluster_issuer     = local.vinnel_cloud_cluster_issuer
  ingress_class_name = module.platform_core.ingress_class_name
  site_service_name  = module.vinnel_cloud.service_name
}

# Proxy

## NetBird

module "proxy_netbird" {
  source = "./proxy/netbird"

  depends_on = [module.platform_vpa]

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  node_ip                         = var.node_ip
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["proxy"]
  dashboard_oidc_client_secret    = module.identity_authelia.netbird_dashboard_oidc_client_secret
  adguard_peer_ids                = module.adguard.peer_ids
}

# Apps

## AdGuard

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

## Admin

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

## GitLab

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

## Mail

module "mail" {
  source = "./apps/mail"

  zone_id = module.platform_core.zone_id_vinnel_cloud
}

## Matrix

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

## Miniflux

module "miniflux" {
  source = "./apps/miniflux"

  depends_on = [module.platform_vpa]

  zone_id            = module.platform_core.zone_id_vinnel_cloud
  relay_ip           = module.platform_relay.ipv4
  cluster_issuer     = local.vinnel_cloud_cluster_issuer
  ingress_class_name = module.platform_core.ingress_class_name
}

## Nextcloud

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

## Registry Cache

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

## SearXNG

module "searxng" {
  source = "./apps/searxng"

  depends_on = [module.platform_core, module.platform_vpa]

  zone_id                           = module.platform_core.zone_id_vinnel_cloud
  relay_ip                          = module.platform_relay.ipv4
  cluster_issuer                    = local.vinnel_cloud_cluster_issuer
  authelia_forward_auth_annotations = local.authelia_forward_auth_annotations
}

## SeaweedFS

module "seaweedfs" {
  source = "./apps/seaweedfs"

  depends_on = [module.platform_core, module.platform_vpa]

  namespace                       = module.platform_storage.namespace
  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  admin_frame_service_annotations = local.admin_framed_service_annotations["seaweed"]
}

## Shell

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

# Games

## Minecraft

module "minecraft" {
  source = "./games/minecraft"

  depends_on = [module.platform_vpa]

  zone_id                   = module.platform_core.zone_id_vin_moe
  relay_ip                  = module.platform_relay.ipv4
  dashboard_namespace       = module.vinnel_cloud.namespace
  minecraft_modpack_zip_url = var.minecraft_modpack_zip_url
  curseforge_api_key        = var.curseforge_api_key
}

## Satisfactory

module "satisfactory" {
  source = "./games/satisfactory"

  depends_on = [module.platform_vpa]

  namespace                   = module.minecraft.namespace
  zone_id                     = module.platform_core.zone_id_vin_moe
  relay_ip                    = module.platform_relay.ipv4
  dashboard_namespace         = module.vinnel_cloud.namespace
  satisfactory_admin_password = var.satisfactory_admin_password
}

## Sleeper

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

# Sites

## vin.moe

module "vin_moe" {
  source = "./sites/vin-moe"

  depends_on = [module.platform_core, module.gitlab]

  zone_id                   = module.platform_core.zone_id_vin_moe
  relay_ip                  = module.platform_relay.ipv4
  cluster_issuer            = local.vin_moe_cluster_issuer
  registry_dockerconfigjson = module.gitlab.registry_dockerconfigjson
  images                    = local.images
}

## vinnel.cloud

module "vinnel_cloud" {
  source = "./sites/vinnel-cloud"

  depends_on = [module.platform_core, module.gitlab]

  zone_id                   = module.platform_core.zone_id_vinnel_cloud
  relay_ip                  = module.platform_relay.ipv4
  cluster_issuer            = local.vinnel_cloud_cluster_issuer
  registry_dockerconfigjson = module.gitlab.registry_dockerconfigjson
  images                    = local.images
}
