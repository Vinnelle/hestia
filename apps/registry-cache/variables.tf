variable "zone_id" {
  description = "Cloudflare zone ID the registry cache hostname attaches to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP the registry cache A record points to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the registry cache TLS certificate"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the registry cache ingress is served by"
  type        = string
}

variable "docker_hub_username" {
  description = "Docker Hub username the cache pulls upstream images with"
  type        = string
}

variable "docker_hub_access_token" {
  description = "Docker Hub access token the cache pulls upstream images with"
  type        = string
  sensitive   = true
}

variable "gitlab_project_id" {
  description = "GitLab project ID the registry cache CI/CD variables are set on"
  type        = string
}
