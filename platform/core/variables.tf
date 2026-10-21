variable "cloudflare_api_token" {
  description = "Cloudflare API token cert-manager uses for DNS-01 solving"
  type        = string
  sensitive   = true
}

variable "cluster_issuers" {
  description = "Let's Encrypt ClusterIssuers to create, as name => ACME account email; each solves DNS-01 through the Cloudflare token"
  type        = map(string)
}
