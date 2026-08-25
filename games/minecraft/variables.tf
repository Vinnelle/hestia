variable "zone_id" {
  description = "Cloudflare zone ID the Minecraft hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the Minecraft A record points to"
  type        = string
}

variable "dashboard_namespace" {
  description = "Namespace the admin dashboard runs in, allowed to reach the server's RCON port"
  type        = string
}

variable "minecraft_modpack_zip_url" {
  description = "URL the server downloads its modpack archive from"
  type        = string
}

variable "curseforge_api_key" {
  description = "CurseForge API key the modpack installer authenticates with"
  type        = string
  sensitive   = true
}
