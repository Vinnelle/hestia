# Core

module "platform_core" {
  source = "./platform/core"

  cloudflare_api_token = var.cloudflare_api_token
  cluster_issuers = {
    (local.vin_moe_cluster_issuer)      = var.acme_email_vin_moe
    (local.vinnel_cloud_cluster_issuer) = var.acme_email_vinnel_cloud
  }
}

# Relay

module "platform_relay" {
  source = "./platform/relay"

  forwards = local.relay_forwards
}

# Proxmox

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

# VPA

module "platform_vpa" {
  source = "./platform/vpa"

  platform_namespace      = module.platform_core.namespace
  observability_namespace = module.observability_grafana.namespace
}

# CNI

module "platform_cni" {
  source = "./platform/cni"

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["hubble"]
}

# Storage

module "platform_storage" {
  source = "./platform/storage"
}

# GPU

module "platform_gpu" {
  source = "./platform/gpu"

  namespace = module.platform_core.namespace
}

# Backup

module "platform_backup" {
  source = "./platform/backup"

  providers = {
    aws.mega_s4 = aws.mega_s4
  }

  mega_s4_endpoint_domain = var.mega_s4_endpoint_domain
}

# CI

module "platform_ci" {
  source = "./platform/ci"

  forge_namespace = module.gitlab.namespace
  deploy_namespaces = toset([
    module.vin_moe.namespace,
    module.vinnel_cloud.namespace,
    module.gemma.namespace,
  ])
  cluster_name           = var.cluster_name
  node_ip                = var.node_ip
  cluster_ca_certificate = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
}

# Trivy

module "platform_trivy" {
  source = "./platform/trivy"

  depends_on = [module.platform_vpa, module.observability_grafana]

  namespace = module.platform_core.namespace
}

# Chaos Mesh

module "platform_chaos_mesh" {
  source = "./platform/chaos-mesh"

  namespace = module.platform_core.namespace
  site_namespaces = sort(tolist(toset([
    module.vin_moe.namespace,
    module.vinnel_cloud.namespace,
  ])))
}

# Job Reaper

module "platform_job_reaper" {
  source = "./platform/job-reaper"

  namespace = module.platform_core.namespace
}

# Terraform Mirror

module "platform_terraform_mirror" {
  source = "./platform/terraform-mirror"

  region            = var.linode_region
  gitlab_project_id = module.gitlab.project_id
}

# Network Policy

module "platform_network_policy" {
  source = "./platform/network-policy"

  depends_on = [
    module.platform_cni,
    module.identity_authelia,
    module.adguard,
    module.automations,
    module.nextcloud,
    module.gitlab,
    module.llm,
    module.matrix,
    module.miniflux,
    module.gemma,
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
