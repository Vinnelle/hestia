variable "namespace" {
  description = "Namespace the browser shell runs in"
  type        = string
}

variable "registry_secret_name" {
  description = "Name of the dockerconfigjson Secret pulling the shell image"
  type        = string
}

variable "image" {
  description = "Shell container image reference"
  type        = string
}

variable "admin_service_account_name" {
  description = "ServiceAccount the shell runs as, granting it the admin dashboard's cluster access"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID the shell hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the shell A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the shell TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the shell ingress is served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing the shell in the admin dashboard"
  type        = map(string)
}
