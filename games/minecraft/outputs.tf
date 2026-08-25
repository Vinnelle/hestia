output "namespace" {
  description = "Namespace the game servers share"
  value       = kubernetes_namespace_v1.games.metadata[0].name
}

output "rcon_secret_name" {
  description = "Name of the Secret holding the Minecraft RCON admin password"
  value       = kubernetes_secret_v1.minecraft_rcon_admin.metadata[0].name
}

output "dns_record_name" {
  description = "Hostname the Minecraft server is reachable at"
  value       = cloudflare_dns_record.mc_vin_moe.name
}
