variable "namespace" {
  description = "Namespace Velero runs in"
  type        = string
}

variable "mega_s4_access_key" {
  description = "Access key for the Mega S4 bucket Velero writes backups to"
  type        = string
  sensitive   = true
}

variable "mega_s4_secret_key" {
  description = "Secret key for the Mega S4 bucket Velero writes backups to"
  type        = string
  sensitive   = true
}

variable "mega_s4_endpoint_domain" {
  description = "Domain of the Mega S4 endpoint Velero writes backups to"
  type        = string
}

variable "seaweedfs_s3_access_key" {
  description = "SeaweedFS S3 access key Velero uses for in-cluster snapshots"
  type        = string
  sensitive   = true
}

variable "seaweedfs_s3_secret_key" {
  description = "SeaweedFS S3 secret key Velero uses for in-cluster snapshots"
  type        = string
  sensitive   = true
}
