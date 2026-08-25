output "namespace" {
  description = "Namespace Nextcloud runs in"
  value       = kubernetes_namespace_v1.files.metadata[0].name
}

output "oidc_client_secret_hash" {
  description = "bcrypt hash of the Nextcloud OIDC client secret, registered with Authelia"
  value       = random_password.nextcloud_oidc_client_secret.bcrypt_hash
  sensitive   = true
}
