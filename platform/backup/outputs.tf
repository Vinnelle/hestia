output "namespace" {
  description = "Namespace holding the backup tooling"
  value       = kubernetes_namespace_v1.backup.metadata[0].name
}

output "s3_credentials_secret_name" {
  description = "Name of the Secret holding the backup bucket credentials"
  value       = kubernetes_secret_v1.s3_backup_credentials.metadata[0].name
}
