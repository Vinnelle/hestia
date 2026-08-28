variable "zone_id" {
  description = "Cloudflare zone ID the GlitchTip hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the GlitchTip A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the GlitchTip TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the GlitchTip ingress is served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations wiring the GlitchTip UI into the admin dashboard"
  type        = map(string)
}

variable "resend_api_key" {
  description = "Resend API key GlitchTip uses for outbound mail"
  type        = string
  sensitive   = true
}
