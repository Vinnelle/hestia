variable "zone_id" {
  description = "Cloudflare zone ID the auth hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the auth A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the auth portal TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the Authelia ingress is served by"
  type        = string
}

variable "resend_api_key" {
  description = "Resend API key Authelia sends notification mail with"
  type        = string
  sensitive   = true
}

variable "nextcloud_oidc_client_secret_hash" {
  description = "bcrypt hash of the Nextcloud OIDC client secret"
  type        = string
  sensitive   = true
}

variable "velero_ui_oidc_client_secret_hash" {
  description = "bcrypt hash of the Velero UI OIDC client secret"
  type        = string
  sensitive   = true
}
