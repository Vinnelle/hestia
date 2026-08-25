output "service_account_name" {
  description = "ServiceAccount the dashboard runs as, reused by the browser shell"
  value       = kubernetes_service_account_v1.vinnel_cloud_admin.metadata[0].name
}
