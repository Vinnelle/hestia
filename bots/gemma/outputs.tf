output "namespace" {
  description = "Namespace holding Gemma"
  value       = kubernetes_namespace_v1.bots.metadata[0].name
}
