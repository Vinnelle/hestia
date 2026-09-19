output "namespace" {
  description = "Namespace holding Synapse and its Postgres"
  value       = kubernetes_namespace_v1.matrix.metadata[0].name
}
