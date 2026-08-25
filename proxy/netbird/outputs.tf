output "namespace" {
  description = "Namespace the NetBird control plane runs in"
  value       = kubernetes_namespace_v1.proxy.metadata[0].name
}

output "devices_group_id" {
  description = "NetBird group ID holding the personal devices, targeted by the AdGuard nameserver group"
  value       = netbird_group.devices.id
}
