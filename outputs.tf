output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "talos_iso_url" {
  description = "Image Factory Secure Boot ISO the Talos VM boots into maintenance mode from"
  value       = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/${local.talos_version}/metal-amd64-secureboot.iso"
}

output "relay_ip" {
  description = "Public IPv4 of the relay -- every public hostname points at it"
  value       = module.platform_relay.ipv4
}

output "pbs_encryption_key" {
  description = "Key every VM backup is encrypted with before it reaches PBS; keep a copy offline next to the state export"
  value       = module.platform_proxmox.pbs_encryption_key
  sensitive   = true
}

output "pbs_bucket" {
  description = "MEGA S4 bucket for the Proxmox Backup Server datastore on the host"
  value       = module.platform_backup.bucket
}

output "import_bucket" {
  description = "MEGA S4 bucket the Nextcloud import reads nextcloud-import/ from"
  value       = module.platform_backup.import_bucket
}

output "mega_s3_endpoint" {
  description = "MEGA S4 endpoint for Proxmox Backup Server's S3 client and the import"
  value       = module.platform_backup.s3_endpoint
}

output "relay_instance_id" {
  description = "Relay instance ID -- its console log shows the boot status, since the relay has no login at all"
  value       = module.platform_relay.instance_id
}

output "authelia_admin_password" {
  value     = module.identity_authelia.admin_password
  sensitive = true
}

output "shell_ttyd_password" {
  value     = module.shell.ttyd_password
  sensitive = true
}

output "seaweedfs_disk_encryption_key" {
  value     = random_password.seaweedfs_disk_encryption_key.result
  sensitive = true
}

output "gitlab_root_password" {
  value     = module.gitlab.root_password
  sensitive = true
}

output "miniflux_admin_password" {
  value     = module.miniflux.admin_password
  sensitive = true
}

output "terraform_provider_mirror_url" {
  description = "Base URL for the provider_installation network_mirror block CI writes into .terraformrc -- must match TF_PROVIDER_MIRROR_URL in .gitlab-ci.yml."
  value       = module.platform_terraform_mirror.terraform_provider_mirror_url
}

output "ci_kubeconfig" {
  description = "Namespace-scoped kubeconfig for GitHub Actions (KUBECONFIG secret)."
  sensitive   = true
  value       = module.platform_ci.ci_kubeconfig
}
