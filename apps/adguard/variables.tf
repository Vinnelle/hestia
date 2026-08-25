variable "zone_id" {
  description = "Cloudflare zone ID the AdGuard admin hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the AdGuard admin A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the AdGuard admin TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the AdGuard admin ingress is served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing the AdGuard UI in the admin dashboard"
  type        = map(string)
}

variable "devices_group_id" {
  description = "NetBird group ID the AdGuard nameservers are served to"
  type        = string
}
