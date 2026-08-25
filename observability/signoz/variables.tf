variable "zone_id" {
  description = "Cloudflare zone ID the SigNoz hostnames attach to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the SigNoz A record points to and k8s-infra reports"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name k8s-infra tags its telemetry with"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the SigNoz TLS certificates"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the SigNoz ingresses are served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations framing the SigNoz UI in the admin dashboard"
  type        = map(string)
}
