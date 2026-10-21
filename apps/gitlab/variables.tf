variable "zone_id" {
  description = "Cloudflare zone ID the GitLab hostnames attach to"
  type        = string
}

variable "node_ip" {
  description = "Cluster node IP CI job pods resolve the registry hostnames to, so image pushes and pulls stay on the node"
  type        = string
}

variable "relay_ip" {
  description = "Public relay IP the GitLab A records point to"
  type        = string
}

variable "cluster_issuer" {
  description = "cert-manager ClusterIssuer name issuing the GitLab TLS certificates"
  type        = string
}

variable "ingress_class_name" {
  description = "IngressClass the GitLab ingresses are served by"
  type        = string
}

variable "acme_email_vin_moe" {
  description = "Contact address GitLab notifications are sent from"
  type        = string
}

variable "resend_api_key" {
  description = "Resend API key GitLab sends outbound mail with"
  type        = string
  sensitive   = true
}
variable "gitlab_mirror_github_pat" {
  description = "GitHub PAT the outbound mirror jobs push with"
  type        = string
  sensitive   = true
}

variable "gitlab_tfc_api_token" {
  description = "HCP Terraform API token the pipeline reads and writes the workspace state with"
  type        = string
  sensitive   = true
}

variable "sops_age_key" {
  description = "CI's age identity, published as the hidden SOPS_AGE_KEY that CI decrypts secrets.sops.json with -- the workspace runs in local execution mode, so HCP Terraform supplies no variables"
  type        = string
  sensitive   = true
}

variable "docker_hub_username" {
  description = "Docker Hub username backing the group dependency proxy"
  type        = string
}

variable "docker_hub_access_token" {
  description = "Docker Hub access token backing the group dependency proxy"
  type        = string
  sensitive   = true
}

variable "seaweedfs_s3_access_key" {
  description = "SeaweedFS S3 access key the container registry stores images with"
  type        = string
  sensitive   = true
}

variable "seaweedfs_s3_secret_key" {
  description = "SeaweedFS S3 secret key the container registry stores images with"
  type        = string
  sensitive   = true
}

variable "ci_kubeconfig" {
  description = "Namespace-scoped kubeconfig CI deploys the sites with"
  type        = string
  sensitive   = true
}
