variable "forwards" {
  description = "Public ports the relay forwards to the node, as in platform/relay/forwards.json"
  type = map(object({
    protocol = string
    port     = number
  }))
}

variable "private_key" {
  description = "Relay's WireGuard private key"
  type        = string
  sensitive   = true
}

variable "node_public_key" {
  description = "Node's WireGuard public key"
  type        = string
}

variable "relay_address" {
  description = "Relay's address inside the WireGuard subnet"
  type        = string
}

variable "node_address" {
  description = "Node's address inside the WireGuard subnet"
  type        = string
}

variable "wireguard_port" {
  description = "UDP port the relay's WireGuard listens on"
  type        = number
}

variable "metrics_port" {
  description = "TCP port node-exporter listens on, on the relay's WireGuard address"
  type        = number
}
