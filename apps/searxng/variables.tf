variable "zone_id" {
  description = "Cloudflare zone ID the search.vinnel.cloud record attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the search.vinnel.cloud A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the ingress TLS certificate"
  type        = string
}

variable "authelia_forward_auth_annotations" {
  description = "Ingress annotations wiring the host into Authelia forward auth"
  type        = map(string)
}
