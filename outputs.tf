output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
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

output "glitchtip_sentry_dsn" {
  description = "Public DSN for the gaia GlitchTip project"
  sensitive   = true
  value       = module.glitchtip.sentry_dsn
}
