variable "region" {
  description = "Linode region the provider mirror bucket lives in"
  type        = string
}

variable "gitlab_project_id" {
  description = "GitLab project ID the provider mirror's CI/CD variables are set on"
  type        = string
}
