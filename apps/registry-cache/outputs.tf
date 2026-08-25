output "namespace" {
  description = "Namespace the registry pull-through cache runs in"
  value       = kubernetes_namespace_v1.registry.metadata[0].name
}
