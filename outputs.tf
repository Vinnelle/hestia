output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "authelia_admin_password" {
  value     = random_password.authelia_admin_password.result
  sensitive = true
}

output "shell_ttyd_password" {
  value     = random_password.shell_ttyd.result
  sensitive = true
}

output "seaweedfs_disk_encryption_key" {
  value     = random_password.seaweedfs_disk_encryption_key.result
  sensitive = true
}

output "gitlab_root_password" {
  value     = random_password.gitlab_root_password.result
  sensitive = true
}

output "wwv_postgres_password" {
  value     = random_password.wwv_postgres_password.result
  sensitive = true
}

output "wwv_redis_password" {
  value     = random_password.wwv_redis_password.result
  sensitive = true
}
