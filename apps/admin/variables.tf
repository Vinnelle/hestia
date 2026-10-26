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
variable "node_ip" {
  description = "Cluster node IP the dashboard reaches the host-network game servers on"
  type        = string
}

variable "relay_ip" {
  description = "Public relay IP the dashboard's A records point to"
  type        = string
}

variable "relay_address" {
  description = "Relay's tunnel address, where its Prometheus endpoint listens"
  type        = string
}

variable "relay_metrics_port" {
  description = "Port of the relay's Prometheus endpoint the dashboard scrapes for its Servers pages"
  type        = number
}

variable "relay_location" {
  description = "Where the relay runs, shown next to it on the dashboard"
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

variable "llm_model" {
  description = "Model name the LLM page of the dashboard shows"
  type        = string
}
