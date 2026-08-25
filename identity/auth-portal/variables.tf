variable "namespace" {
  description = "Namespace the auth portal runs in"
  type        = string
}

variable "registry_secret_name" {
  description = "Name of the dockerconfigjson Secret pulling the auth portal image"
  type        = string
}

variable "image" {
  description = "Auth portal container image reference"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the auth portal ingress is served by"
  type        = string
}
