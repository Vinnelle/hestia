variable "flavor" {
  description = "Infomaniak Public Cloud flavor for the relay -- it runs from RAM and only forwards packets, so the smallest one with a local disk is plenty"
  type        = string
  default     = "a1-ram2-disk20-perf1"
}

variable "network" {
  description = "Infomaniak's public network: a port on it carries a public IPv4 directly, with no router or floating IP in between"
  type        = string
  default     = "ext-net1"
}

variable "forwards" {
  description = "Public ports the relay forwards to the Talos node over WireGuard, keyed by a short name that labels the matching firewall rules and metrics"
  type = map(object({
    protocol = string
    port     = number
  }))

  validation {
    condition     = alltrue([for f in values(var.forwards) : contains(["tcp", "udp"], f.protocol)])
    error_message = "Every forward's protocol must be tcp or udp."
  }

  validation {
    condition     = alltrue([for name in keys(var.forwards) : can(regex("^[a-z][a-z0-9-]*$", name))])
    error_message = "Forward names must be lowercase letters, digits and hyphens."
  }
}
