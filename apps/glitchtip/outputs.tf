output "namespace" {
  description = "Namespace holding GlitchTip and its dependencies"
  value       = kubernetes_namespace_v1.glitchtip.metadata[0].name
}

output "url" {
  description = "GlitchTip URL"
  value       = local.glitchtip_url
}

output "sentry_dsn" {
  description = "Public DSN for the gaia GlitchTip project"
  value       = glitchtip_project_key.gaia.dsn["public"]
  sensitive   = true
}
