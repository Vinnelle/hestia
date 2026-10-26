variable "image" {
  description = "Digest-pinned automations image"
  type        = string
}

variable "registry_dockerconfigjson" {
  description = "dockerconfigjson that pulls from artifacts.vinnel.cloud"
  type        = string
  sensitive   = true
}

variable "node_ip" {
  description = "Node IP that ingress-nginx listens on, which gitlab.vinnel.cloud is pinned to so the API calls never leave the node"
  type        = string
}

variable "observability_namespace" {
  description = "Namespace running the OpenTelemetry Collector the service sends traces to"
  type        = string
}

variable "gitlab_project_id" {
  description = "ID of the gaia project whose Renovate merge requests get reviewed"
  type        = string
}

variable "renovate_author_id" {
  description = "GitLab user ID Renovate opens merge requests as; merge requests from anyone else are refused"
  type        = number
}

variable "llm_base_url" {
  description = "Base URL of the OpenAI-compatible API the reviewer asks, ending in /v1. Empty keeps everything but the namespace off"
  type        = string
}

variable "llm_model" {
  description = "Model name to send to llm_base_url"
  type        = string
}

variable "llm_api_key" {
  description = "Bearer token llm_base_url requires"
  type        = string
  sensitive   = true
}

variable "resend_api_key" {
  description = "Resend API key the morning digest is sent with"
  type        = string
  sensitive   = true
}

variable "digest_to" {
  description = "Address the morning digest goes to"
  type        = string
}
