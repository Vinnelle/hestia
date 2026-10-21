output "ipv4" {
  description = "Public IPv4 address of the relay; it belongs to the port, so it survives rebuilds of the instance"
  value       = local.ipv4
  depends_on  = [openstack_compute_instance_v2.relay]
}

output "endpoint" {
  description = "WireGuard endpoint the Talos node dials"
  value       = "${local.ipv4}:${local.wireguard_port}"
  depends_on  = [openstack_compute_instance_v2.relay]
}

output "public_key" {
  description = "Relay's WireGuard public key"
  value       = wireguard_asymmetric_key.relay.public_key
}

output "node_private_key" {
  description = "Talos node's WireGuard private key"
  value       = wireguard_asymmetric_key.node.private_key
  sensitive   = true
}

output "subnet" {
  description = "WireGuard subnet between relay and node; relayed traffic reaches the node from the relay's address in it"
  value       = local.subnet
}

output "relay_address" {
  description = "Relay's address inside the WireGuard subnet"
  value       = local.relay_address
}

output "node_address" {
  description = "Node's WireGuard interface address, in CIDR form"
  value       = "${local.node_address}/24"
}

output "metrics_port" {
  description = "Port of the Prometheus endpoint the relay serves on its tunnel address -- only the node can reach it"
  value       = local.metrics_port
}

output "instance_id" {
  description = "Relay instance ID; its boot status shows in its console log, since it has no login at all"
  value       = openstack_compute_instance_v2.relay.id
}
