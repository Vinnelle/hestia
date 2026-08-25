output "oidc_client_secret_hash" {
  description = "bcrypt hash of the Velero UI OIDC client secret, registered with Authelia"
  value       = random_password.velero_ui_oidc_client_secret.bcrypt_hash
  sensitive   = true
}
