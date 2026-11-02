output "namespace" {
  description = "Namespace the NetBird control plane runs in"
  value       = kubernetes_namespace_v1.proxy.metadata[0].name
}

output "devices_group_id" {
  description = "NetBird group ID holding the personal devices, targeted by the AdGuard nameserver group"
  value       = netbird_group.devices.id
}

output "network_range" {
  description = "CIDR NetBird hands peer addresses out of"
  value       = netbird_account_settings.main.network_range
}

output "pve_ip" {
  description = "NetBird address of the Proxmox host, which AdGuard answers pve.vinnel.cloud with"
  value       = data.netbird_peer.pve.ip
}
