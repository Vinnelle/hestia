output "s3_access_key" {
  description = "SeaweedFS S3 access key other workloads authenticate with"
  value       = random_password.seaweedfs_s3_access_key.result
  sensitive   = true
}

output "s3_secret_key" {
  description = "SeaweedFS S3 secret key other workloads authenticate with"
  value       = random_password.seaweedfs_s3_secret_key.result
  sensitive   = true
}
