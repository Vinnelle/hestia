variable "zone_id" {
  description = "Cloudflare zone ID the Hubble UI hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the Hubble UI A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the Hubble UI TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the Hubble UI ingress is served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing the Hubble UI in the admin dashboard"
  type        = map(string)
}
