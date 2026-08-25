output "terraform_provider_mirror_url" {
  description = "Base URL for the provider_installation network_mirror block CI writes into .terraformrc -- must match TF_PROVIDER_MIRROR_URL in .gitlab-ci.yml."
  value       = "https://s3.${var.mega_s4_endpoint_domain}/${aws_s3_bucket.terraform_provider_mirror.bucket}/"
}
