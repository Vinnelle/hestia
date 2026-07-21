output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "harbor_ci_username" {
  value     = harbor_robot_account.ci.full_name
  sensitive = true
}

output "harbor_ci_password" {
  value     = random_password.harbor_robot.result
  sensitive = true
}

output "authelia_admin_password" {
  value     = random_password.authelia_admin_password.result
  sensitive = true
}

output "momus_ssh_address" {
  value = "ssh -p 2222 ida@${data.netbird_peer.momus.ip}"
}

output "momus_root_password" {
  value     = random_password.momus_root.result
  sensitive = true
}

output "momus_ida_sudo_password" {
  value     = random_password.momus_ida_sudo.result
  sensitive = true
}
