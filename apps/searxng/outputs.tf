output "namespace" {
  description = "Namespace holding SearXNG"
  value       = kubernetes_namespace_v1.searxng.metadata[0].name
}
