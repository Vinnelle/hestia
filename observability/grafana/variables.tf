variable "zone_id" {
  description = "Cloudflare zone ID the Grafana hostname attaches to"
  type        = string
}

variable "relay_ip" {
  description = "Public relay IP the Grafana A record points to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the control-plane and etcd metrics are scraped on, and that Grafana reaches Authelia through"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name every metric is labelled with"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the Grafana TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the Grafana ingress is served by"
  type        = string
}

variable "admin_frame_service_annotations" {
  description = "Ingress annotations putting Grafana behind Authelia and framing it in the admin dashboard"
  type        = map(string)
}

variable "alert_email" {
  description = "Address Alertmanager mails alerts to"
  type        = string
}

variable "resend_api_key" {
  description = "Resend API key Alertmanager authenticates to smtp.resend.com with"
  type        = string
  sensitive   = true
}

variable "sidecar_image" {
  description = "Grafana's k8s-sidecar image as registry/repository[:tag]@sha256:digest, the patched build recorded in observability-images.json"
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^:@]+(:[^@]+)?@sha256:[0-9a-f]{64}$", var.sidecar_image))
    error_message = "sidecar_image must be registry/repository[:tag]@sha256:<digest>."
  }
}

variable "registry_dockerconfigjson" {
  description = "dockerconfigjson that pulls from artifacts.vinnel.cloud"
  type        = string
  sensitive   = true
}
