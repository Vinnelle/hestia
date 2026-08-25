output "namespace" {
  description = "Namespace holding Miniflux and its Postgres"
  value       = kubernetes_namespace_v1.miniflux.metadata[0].name
}

output "admin_password" {
  description = "Password for the Miniflux admin user"
  value       = random_password.miniflux_admin_password.result
  sensitive   = true
}
