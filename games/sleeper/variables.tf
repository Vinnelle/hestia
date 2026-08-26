variable "namespace" {
  description = "Namespace the game servers share, and the one this sleeper scales deployments in"
  type        = string
}

variable "image" {
  description = "Image to run — the vinnel-cloud admin image, whose ROLE=game-sleeper mode is this workload"
  type        = string
}

variable "registry_dockerconfigjson" {
  description = "dockerconfigjson for the private registry the admin image is pulled from"
  type        = string
  sensitive   = true
}

variable "node_ip" {
  description = "Node IP the game servers bind their host-network ports on"
  type        = string
}

variable "minecraft_port" {
  description = "TCP port the Minecraft server listens on, held by the sleeper while the server is scaled to 0"
  type        = number
  default     = 25565
}

variable "satisfactory_admin_password" {
  description = "Satisfactory admin password, used to read the connected player count. Held in this namespace's own Secret because the dashboard's copy lives in the vinnel-cloud namespace and a Secret cannot be referenced across one."
  type        = string
  sensitive   = true
}

variable "idle_timeout" {
  description = "How long a server must report zero players before it is scaled to 0"
  type        = string
  default     = "20m"
}

variable "poll_interval" {
  description = "How often each server's player count is checked"
  type        = string
  default     = "60s"
}

variable "observability_namespace" {
  description = "Namespace running the collector telemetry is shipped to"
  type        = string
}
