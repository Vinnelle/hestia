variable "namespace" {
  description = "Namespace Chaos Mesh runs in"
  type        = string
}

variable "site_namespaces" {
  description = "Namespaces the pod-kill and stress experiments target"
  type        = list(string)
}
