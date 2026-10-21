output "terraform_provider_mirror_url" {
  description = "Base URL of the provider mirror CI's terraform_provider_mirror_sync fills, for a provider_installation network_mirror block"
  value       = "https://${linode_object_storage_bucket.terraform_provider_mirror.hostname}/"
}
