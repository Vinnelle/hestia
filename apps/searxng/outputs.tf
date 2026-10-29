output "namespace" {
  description = "Namespace holding SearXNG"
  value       = kubernetes_namespace_v1.searxng.metadata[0].name
}

output "url" {
  description = "In-cluster base URL of SearXNG, whose JSON format the bots' search tool uses"
  value       = "http://${kubernetes_service_v1.searxng.metadata[0].name}.${kubernetes_namespace_v1.searxng.metadata[0].name}.svc.cluster.local"
}
