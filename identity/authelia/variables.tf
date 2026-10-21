variable "zone_id" {
  description = "Cloudflare zone ID the auth hostname attaches to"
  type        = string
}

variable "relay_ip" {
  description = "Public relay IP the auth A record points to"
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

variable "grafana_oidc_client_secret_hash" {
  description = "bcrypt hash of the Grafana OIDC client secret"
  type        = string
  sensitive   = true
}
