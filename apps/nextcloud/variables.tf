variable "zone_id" {
  description = "Cloudflare zone ID the Nextcloud hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the Nextcloud A record points to"
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

variable "mega_import_user" {
  description = "Mega account the one-off import job pulls files from"
  type        = string
  sensitive   = true
}

variable "mega_import_pass" {
  description = "Password for the Mega account the import job pulls files from"
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
