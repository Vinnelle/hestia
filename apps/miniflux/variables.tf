variable "zone_id" {
  description = "Cloudflare zone ID the Miniflux hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the Miniflux A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the Miniflux TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the Miniflux ingress is served by"
  type        = string
}
