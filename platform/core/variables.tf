variable "cloudflare_api_token" {
  description = "Cloudflare API token cert-manager uses for DNS-01 solving"
  type        = string
  sensitive   = true
}
