output "namespace" {
  description = "Namespace holding the storage provisioner and its PVs"
  value       = kubernetes_namespace_v1.storage.metadata[0].name
}
