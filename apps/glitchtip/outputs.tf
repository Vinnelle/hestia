output "namespace" {
  description = "Namespace holding GlitchTip and its dependencies"
  value       = kubernetes_namespace_v1.glitchtip.metadata[0].name
}

output "url" {
  description = "GlitchTip URL"
  value       = local.glitchtip_url
}
