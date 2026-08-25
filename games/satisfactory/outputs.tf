output "admin_secret_name" {
  description = "Name of the Secret holding the Satisfactory admin password"
  value       = kubernetes_secret_v1.satisfactory_admin.metadata[0].name
}

output "saves_service_name" {
  description = "Name of the Service exposing the Satisfactory save files"
  value       = kubernetes_service_v1.satisfactory_saves.metadata[0].name
}
