variable "namespace" {
  description = "Namespace the status page ingress lives in"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID the status hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the status A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the status page TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the status page ingress is served by"
  type        = string
}

variable "site_service_name" {
  description = "Name of the vinnel.cloud site Service the status host is routed to"
  type        = string
}
