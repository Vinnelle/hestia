output "bucket" {
  description = "MEGA S4 bucket the Proxmox Backup Server datastore on the host writes the Talos VM's encrypted backups to"
  value       = aws_s3_bucket.pbs.bucket
}

output "import_bucket" {
  description = "MEGA S4 bucket the one-off Nextcloud import reads nextcloud-import/ from"
  value       = aws_s3_bucket.import.bucket
}

output "s3_endpoint" {
  description = "MEGA S4 S3 endpoint both buckets live behind"
  value       = "s3.${var.mega_s4_endpoint_domain}"
}
