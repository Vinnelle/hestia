variable "zone_id" {
  description = "Cloudflare zone ID the Nextcloud hostname attaches to"
  type        = string
}

variable "relay_ip" {
  description = "Public relay IP the Nextcloud A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the Nextcloud TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the Nextcloud ingress is served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing Nextcloud in the admin dashboard"
  type        = map(string)
}

variable "import_s3_endpoint" {
  description = "MEGA S4 endpoint the one-off import job reads nextcloud-import/ from"
  type        = string
}

variable "import_s3_bucket" {
  description = "MEGA S4 bucket the one-off import job reads from"
  type        = string
}

variable "import_s3_access_key" {
  description = "Read-only (S3ObjectReadAccess) MEGA S4 access key the import job reads with"
  type        = string
  sensitive   = true
}

variable "import_s3_secret_key" {
  description = "Secret of that read-only MEGA S4 key"
  type        = string
  sensitive   = true
}

variable "seaweedfs_s3_access_key" {
  description = "SeaweedFS S3 access key Nextcloud stores primary data with"
  type        = string
  sensitive   = true
}

variable "seaweedfs_s3_secret_key" {
  description = "SeaweedFS S3 secret key Nextcloud stores primary data with"
  type        = string
  sensitive   = true
}
