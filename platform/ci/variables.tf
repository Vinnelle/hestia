variable "forge_namespace" {
  description = "Namespace the CI deployer ServiceAccount lives in"
  type        = string
}

variable "deploy_namespaces" {
  description = "Namespaces the CI deployer may patch Deployments in"
  type        = set(string)
}

variable "cluster_name" {
  description = "Cluster name written into the generated kubeconfig"
  type        = string
}

variable "node_ip" {
  description = "API server address the generated kubeconfig points at"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Base64 cluster CA certificate the generated kubeconfig trusts"
  type        = string
  sensitive   = true
}
