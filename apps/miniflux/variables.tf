variable "zone_id" {
  description = "Cloudflare zone ID the Miniflux hostname attaches to"
  type        = string
}

variable "relay_ip" {
  description = "Public relay IP the Miniflux A record points to"
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

variable "postgres_image" {
  description = "Postgres image Miniflux's database runs, the patched build recorded in app-images.json"
  type        = string
}

variable "registry_dockerconfigjson" {
  description = "dockerconfigjson that pulls from artifacts.vinnel.cloud"
  type        = string
  sensitive   = true
}
