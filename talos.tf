resource "random_password" "seaweedfs_disk_encryption_key" {
  length  = 64
  special = false
}

resource "talos_machine_secrets" "this" {}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/nvidia-container-toolkit-lts",
          "siderolabs/nvidia-open-gpu-kernel-modules-lts",
          "siderolabs/qemu-guest-agent",
        ]
      }
    }
  })
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.node_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = "v1.13.9"
  kubernetes_version = "v1.37.2"

  config_patches = [
    file("${path.module}/talos/controlplane-patch.yaml"),
    file("${path.module}/talos/cilium-cni-patch.yaml"),
    file("${path.module}/talos/nvidia-gpu-patch.yaml"),
    templatefile("${path.module}/talos/firewall.yaml.tftpl", {
      node_ip      = var.node_ip
      lan_cidr     = var.lan_cidr
      relay_subnet = module.platform_relay.subnet
      forwards     = local.relay_forwards
    }),
    templatefile("${path.module}/talos/network.yaml.tftpl", {
      node_ip          = var.node_ip
      wg_address       = module.platform_relay.node_address
      wg_private_key   = module.platform_relay.node_private_key
      relay_public_key = module.platform_relay.public_key
      relay_endpoint   = module.platform_relay.endpoint
      relay_address    = module.platform_relay.relay_address
    }),
    templatefile("${path.module}/talos/seaweedfs-disks-patch.yaml.tftpl", {
      encryption_key = random_password.seaweedfs_disk_encryption_key.result
      serials        = module.platform_proxmox.disk_serials
    }),
    yamlencode({
      machine = {
        install = {
          diskSelector = {
            serial = module.platform_proxmox.disk_serials.system
          }
          image = "factory.talos.dev/installer-secureboot/${talos_image_factory_schematic.this.id}:${local.talos_version}"
        }
      }
    }),
  ]
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = var.node_ip
}

resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.node_ip
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [var.node_ip]
  endpoints            = [var.node_ip]
}
