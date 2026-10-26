output "namespace" {
  description = "Namespace holding the automations service"
  value       = kubernetes_namespace_v1.automations.metadata[0].name
}
