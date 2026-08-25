variable "namespace" {
  description = "Namespace the game servers share"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID the Satisfactory hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the Satisfactory A record points to"
  type        = string
}

variable "dashboard_namespace" {
  description = "Namespace the admin dashboard runs in, allowed to reach the saves endpoint"
  type        = string
}

variable "satisfactory_admin_password" {
  description = "Admin password for the Satisfactory server"
  type        = string
  sensitive   = true
}
