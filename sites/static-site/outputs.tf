output "service_name" {
  description = "Name of the site's ClusterIP service, for other ingresses to route to"
  value       = kubernetes_service_v1.this.metadata[0].name
}
