variable "zone_id" {
  description = "Cloudflare zone ID the NetBird hostnames attach to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the NetBird A records point to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the NetBird TLS certificates"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the NetBird ingresses are served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing the NetBird dashboard in the admin dashboard"
  type        = map(string)
}

variable "dashboard_oidc_client_secret" {
  description = "OIDC client secret the dashboard authenticates to Authelia with"
  type        = string
  sensitive   = true
}

variable "adguard_peer_ids" {
  description = "NetBird peer IDs of the AdGuard instances, grouped so DNS policies can target them"
  type        = list(string)
}
