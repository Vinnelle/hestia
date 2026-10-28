variable "namespace" {
  description = "Namespace the default-deny policy is applied to"
  type        = string
}

variable "telemetry_namespace" {
  description = "Namespace running the collector every workload ships telemetry to and that scrapes every workload back"
  type        = string
}

variable "ingress_from" {
  description = "Namespaces allowed to reach this namespace's pods, on top of the baseline"
  type        = list(string)
  default     = []
}

variable "egress_to" {
  description = "Cross-namespace destinations this namespace's pods may reach, on top of the baseline"
  type = list(object({
    namespace = string
    ports     = list(number)
  }))
  default = []
}

variable "egress_telemetry" {
  description = "Whether this namespace's pods may reach the telemetry namespace, to ship traces and logs; a namespace that sends none can leave it closed"
  type        = bool
  default     = true
  nullable    = false
}

variable "egress_world_ports" {
  description = "TCP ports this namespace's pods may reach on any public IPv4 address; private, shared, loopback, link-local and multicast ranges stay closed"
  type        = list(number)
  default     = []
  nullable    = false
}

variable "egress_entities" {
  description = "Cilium entities this namespace's pods may reach on any port; the node, the other nodes and the API server unless a namespace needs none of them"
  type        = list(string)
  default     = ["host", "remote-node", "kube-apiserver"]
  nullable    = false
}

variable "egress_fqdns" {
  description = "Hostname patterns this namespace's pods may reach outside the cluster, on port 443. null keeps the blanket `world` egress entity; a list (empty included) drops `world` and allows only these names, resolved through Cilium's DNS proxy."
  type        = list(string)
  default     = null
}
