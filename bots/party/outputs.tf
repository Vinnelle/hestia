output "namespace" {
  description = "Namespace holding the party bot"
  value       = kubernetes_namespace_v1.party.metadata[0].name
}
