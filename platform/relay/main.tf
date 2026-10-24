locals {
  subnet         = "10.88.0.0/24"
  relay_address  = "10.88.0.1"
  node_address   = "10.88.0.2"
  wireguard_port = 51820
  metrics_port   = 9100
  image          = jsondecode(file("${path.module}/image/image.json"))
  ipv4           = one([for ip in openstack_networking_port_v2.relay.all_fixed_ips : ip if !strcontains(ip, ":")])
}

resource "wireguard_asymmetric_key" "relay" {}

resource "wireguard_asymmetric_key" "node" {}

module "user_data" {
  source = "./user-data"

  forwards        = var.forwards
  private_key     = wireguard_asymmetric_key.relay.private_key
  node_public_key = wireguard_asymmetric_key.node.public_key
  relay_address   = local.relay_address
  node_address    = local.node_address
  wireguard_port  = local.wireguard_port
  metrics_port    = local.metrics_port
}

data "openstack_networking_network_v2" "public" {
  name = var.network
}

resource "openstack_networking_secgroup_v2" "relay" {
  name        = "gaia-relay"
  description = "WireGuard, ICMP and the forwarded ports"
}

resource "openstack_networking_secgroup_rule_v2" "wireguard" {
  security_group_id = openstack_networking_secgroup_v2.relay.id
  description       = "wireguard"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = local.wireguard_port
  port_range_max    = local.wireguard_port
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  security_group_id = openstack_networking_secgroup_v2.relay.id
  description       = "icmp"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "forward" {
  for_each = var.forwards

  security_group_id = openstack_networking_secgroup_v2.relay.id
  description       = each.key
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_port_v2" "relay" {
  name               = "gaia-relay"
  network_id         = data.openstack_networking_network_v2.public.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.relay.id]
}

resource "openstack_compute_instance_v2" "relay" {
  name         = "gaia-relay"
  image_id     = local.image.id
  flavor_name  = var.flavor
  config_drive = true
  user_data    = module.user_data.content
  tags         = ["gaia"]

  network {
    port = openstack_networking_port_v2.relay.id
  }

  depends_on = [
    openstack_networking_secgroup_rule_v2.wireguard,
    openstack_networking_secgroup_rule_v2.icmp,
    openstack_networking_secgroup_rule_v2.forward,
  ]

  lifecycle {
    precondition {
      condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", local.image.id))
      error_message = "No relay image is published to Infomaniak yet: run just relay build and just relay publish first (README, Bootstrap)."
    }
  }
}
