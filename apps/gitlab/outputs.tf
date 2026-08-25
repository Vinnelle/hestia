output "namespace" {
  description = "Namespace GitLab and its runners live in"
  value       = kubernetes_namespace_v1.forge.metadata[0].name
}

output "project_id" {
  description = "ID of the gaia project GitLab hosts"
  value       = gitlab_project.gaia.id
}

output "default_branch" {
  description = "Name of the branch pipelines open merge requests against"
  value       = gitlab_branch.pre.name
}

output "root_password" {
  description = "Password for the GitLab root user"
  value       = random_password.gitlab_root_password.result
  sensitive   = true
}

output "registry_dockerconfigjson" {
  description = "dockerconfigjson pulling images from the in-cluster registry"
  value       = local.registry_dockerconfigjson
  sensitive   = true
}
