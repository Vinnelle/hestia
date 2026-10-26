output "namespace" {
  description = "Namespace holding the LLM server"
  value       = kubernetes_namespace_v1.llm.metadata[0].name
}

output "base_url" {
  description = "OpenAI-compatible base URL of the LLM server, ending in /v1"
  value       = "http://${kubernetes_service_v1.llm.metadata[0].name}.${kubernetes_namespace_v1.llm.metadata[0].name}.svc.cluster.local:${local.port}/v1"
}

output "model" {
  description = "Model name the server answers to"
  value       = local.model.alias
}

output "api_key" {
  description = "Bearer token the LLM server requires"
  value       = random_password.api_key.result
  sensitive   = true
}
