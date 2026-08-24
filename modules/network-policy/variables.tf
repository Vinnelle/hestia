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
