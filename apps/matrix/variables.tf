variable "zone_id" {
  description = "Cloudflare zone ID the Matrix hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the Matrix A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the Matrix TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the Matrix ingress is served by"
  type        = string
}

variable "server_name" {
  description = "Matrix server name baked into every user and room ID (@user:server_name) -- permanent once the first account exists"
  type        = string
}

variable "hostname" {
  description = "Public hostname clients connect to"
  type        = string
}
