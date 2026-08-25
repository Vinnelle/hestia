variable "namespace" {
  description = "Namespace SeaweedFS runs in"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID the SeaweedFS hostnames attach to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the SeaweedFS A records point to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the ingress TLS certificates"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing the SeaweedFS UI in the admin dashboard"
  type        = map(string)
}
