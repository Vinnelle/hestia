variable "namespace" {
  description = "Namespace the admin dashboard runs in"
  type        = string
}

variable "registry_secret_name" {
  description = "Name of the dockerconfigjson Secret pulling the dashboard image"
  type        = string
}

variable "image" {
  description = "Admin dashboard container image reference"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID the dashboard hostnames attach to"
  type        = string
}

variable "blog_zone_id" {
  description = "Cloudflare zone ID holding the blog hostnames the cache purger clears"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the dashboard A records point to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the dashboard TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the dashboard ingress is served by"
  type        = string
}

variable "authelia_forward_auth_annotations" {
  description = "Ingress annotations wiring the dashboard into Authelia forward auth"
  type        = map(string)
}

variable "observability_namespace" {
  description = "Namespace the dashboard ships its traces to"
  type        = string
}

variable "games_namespace" {
  description = "Namespace the game servers share, reached for RCON and save files"
  type        = string
}

variable "minecraft_rcon_secret_name" {
  description = "Name of the Secret holding the Minecraft RCON password"
  type        = string
}

variable "minecraft_dns_record_name" {
  description = "Hostname the Minecraft server is reachable at"
  type        = string
}

variable "satisfactory_saves_service_name" {
  description = "Name of the Service exposing the Satisfactory save files"
  type        = string
}

variable "satisfactory_admin_secret_name" {
  description = "Name of the Secret holding the Satisfactory admin password"
  type        = string
}

variable "gitlab_project_id" {
  description = "ID of the gaia project the dashboard drives pipelines on"
  type        = string
}

variable "gitlab_default_branch" {
  description = "Branch the dashboard opens merge requests against"
  type        = string
}

variable "cloudflare_cache_purge_token" {
  description = "Cloudflare token the dashboard purges the site caches with"
  type        = string
  sensitive   = true
}

variable "sentry_dsn" {
  description = "GlitchTip DSN used by the dashboard to report errors and sampled transactions"
  type        = string
  sensitive   = true
}
