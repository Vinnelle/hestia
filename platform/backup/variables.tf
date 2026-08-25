variable "s3_backup_access_key" {
  description = "Access key for the off-site backup bucket"
  type        = string
  sensitive   = true
}

variable "s3_backup_secret_key" {
  description = "Secret key for the off-site backup bucket"
  type        = string
  sensitive   = true
}

variable "backup_encryption_password" {
  description = "Restic repository password encrypting snapshots client-side"
  type        = string
  sensitive   = true
}
