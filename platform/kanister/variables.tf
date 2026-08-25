variable "namespace" {
  description = "Namespace Kanister runs in"
  type        = string
}

variable "s3_credentials_secret_name" {
  description = "Name of the Secret holding the backup bucket credentials"
  type        = string
}

variable "s3_backup_endpoint" {
  description = "Hostname of the S3 endpoint holding the backup bucket"
  type        = string
}
