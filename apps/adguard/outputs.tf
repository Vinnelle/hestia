output "namespace" {
  description = "Namespace AdGuard runs in"
  value       = kubernetes_namespace_v1.dns.metadata[0].name
}

output "peer_ids" {
  description = "NetBird peer IDs of the AdGuard instances"
  value       = [for ordinal in sort(keys(data.netbird_peer.adguard)) : data.netbird_peer.adguard[ordinal].id]
}
