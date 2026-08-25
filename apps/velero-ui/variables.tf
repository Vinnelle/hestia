variable "namespace" {
  description = "Namespace the Velero UI runs in"
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID the Velero UI hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the Velero UI A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the Velero UI TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the Velero UI ingress is served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing the Velero UI in the admin dashboard"
  type        = map(string)
}
