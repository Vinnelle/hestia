variable "cloudflare_api_token" {
  description = "Cloudflare API token cert-manager uses for DNS-01 solving"
  type        = string
  sensitive   = true
}

variable "cluster_issuers" {
  description = "Let's Encrypt ClusterIssuers to create, as name => ACME account email; each solves DNS-01 through the Cloudflare token"
  type        = map(string)
}

variable "ingress_nginx_image" {
  description = "ingress-nginx controller image as registry/image:tag@sha256:digest"
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^:@]+:[^@]+@sha256:[0-9a-f]{64}$", var.ingress_nginx_image))
    error_message = "ingress_nginx_image must be registry/image:tag@sha256:<digest>."
  }
}

variable "registry_pull_secret" {
  description = "Existing dockerconfigjson Secret for artifacts.vinnel.cloud, copied into the platform namespace by name so this module never depends on the gitlab module"
  type = object({
    namespace = string
    name      = string
  })
}
