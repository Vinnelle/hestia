output "namespace" {
  description = "Namespace holding SigNoz and the cluster telemetry agents"
  value       = kubernetes_namespace_v1.observability.metadata[0].name
}

output "release_id" {
  description = "SigNoz Helm release ID; reading it orders dependents after the install"
  value       = helm_release.signoz.id
}

output "alert_channels" {
  description = "SigNoz notification channels the alerting rules route to"
  value       = local.signoz_alert_channels
}

output "notification_settings" {
  description = "SigNoz notification settings block shared by the alerting rules"
  value       = local.signoz_notification_settings
}
