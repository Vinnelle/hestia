output "namespace" {
  description = "Namespace Authelia runs in"
  value       = kubernetes_namespace_v1.auth.metadata[0].name
}

output "admin_password" {
  description = "Password for the Authelia admin user"
  value       = random_password.authelia_admin_password.result
  sensitive   = true
}

output "netbird_dashboard_oidc_client_secret" {
  description = "OIDC client secret the NetBird dashboard authenticates to Authelia with"
  value       = random_password.netbird_dashboard_oidc_client_secret.result
  sensitive   = true
}
