output "service_account_name" {
  description = "Name of the ServiceAccount the sleeper scales the game deployments with"
  value       = kubernetes_service_account_v1.game_sleeper.metadata[0].name
}
