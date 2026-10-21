output "namespace" {
  description = "Namespace holding Grafana, VictoriaMetrics, Loki, Tempo and the OpenTelemetry Collector"
  value       = kubernetes_namespace_v1.observability.metadata[0].name
}

output "otlp_grpc_endpoint" {
  description = "OTLP/gRPC endpoint workloads send traces, metrics and logs to"
  value       = "otel-collector.${kubernetes_namespace_v1.observability.metadata[0].name}.svc.cluster.local:4317"
}

output "oidc_client_secret_hash" {
  description = "bcrypt hash of the Grafana OIDC client secret, registered with Authelia"
  value       = random_password.grafana_oidc_client_secret.bcrypt_hash
  sensitive   = true
}
