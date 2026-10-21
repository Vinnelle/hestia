variable "zone_id" {
  description = "Cloudflare zone ID the site's records attach to"
  type        = string
}

variable "relay_ip" {
  description = "Public relay IP the site's A records point to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the site's TLS certificate"
  type        = string
}

variable "registry_dockerconfigjson" {
  description = "dockerconfigjson pulling the site image from the in-cluster registry"
  type        = string
  sensitive   = true
}

variable "images" {
  description = "Image references keyed by build slug, as recorded in images.json"
  type        = map(string)
}
