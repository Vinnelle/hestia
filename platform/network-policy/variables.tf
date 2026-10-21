variable "telemetry_namespace" {
  description = "Namespace every policied namespace is allowed to ship telemetry to"
  type        = string
}

variable "relay_address" {
  description = "Relay's WireGuard address. Relayed visitors only ever reach the node itself, so no pod has a reason to accept traffic from it."
  type        = string
}
