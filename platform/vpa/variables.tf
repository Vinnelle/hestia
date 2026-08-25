variable "platform_namespace" {
  description = "Namespace the VPA chart is installed into"
  type        = string
}

variable "observability_namespace" {
  description = "Namespace metrics-server is installed into"
  type        = string
}
