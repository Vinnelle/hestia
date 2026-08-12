variable "site_slug" {
  description = "Dash-separated site identifier, e.g. \"vin-moe\" (drives all k8s/DNS object names)"
  type        = string
}

variable "domain" {
  description = "Site's apex hostname, e.g. \"vin.moe\""
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID the site's DNS/cache rules attach to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the site's apex A record points to"
  type        = string
}

variable "cache_description" {
  description = "Description text for the zone's CDN cache ruleset rule"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name for this site's TLS cert"
  type        = string
}

variable "acme_email" {
  description = "ACME registration email for the site's Let's Encrypt issuer"
  type        = string
}

variable "cloudflare_secret_name" {
  description = "Name of the k8s secret holding the Cloudflare API token, for DNS-01 solving"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy the site into"
  type        = string
}

variable "registry_secret_name" {
  description = "Name of the image-pull secret for the internal registry"
  type        = string
}

variable "image" {
  description = "Fully-qualified nginx image ref for the site"
  type        = string
}

variable "replicas" {
  description = "Deployment replica count"
  type        = number
  default     = 2
}

variable "port_name" {
  description = "Optional name for the container's http port"
  type        = string
  default     = null
}

variable "cpu_request" {
  description = "nginx container CPU request"
  type        = string
}

variable "memory_request" {
  description = "nginx container memory request (also used as the VPA minAllowed)"
  type        = string
}

variable "cpu_limit" {
  description = "nginx container CPU limit"
  type        = string
}

variable "memory_limit" {
  description = "nginx container memory limit (also used as the VPA maxAllowed)"
  type        = string
}

variable "vpa_update_mode" {
  description = "VPA updateMode for the site deployment"
  type        = string
}
