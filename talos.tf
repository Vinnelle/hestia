resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.node_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version = "v1.13.9"

  config_patches = [
    file("${path.module}/talos/controlplane-patch.yaml"),
    templatefile("${path.module}/talos/firewall.yaml.tftpl", {
      node_ip = var.node_ip
    }),
    templatefile("${path.module}/talos/seaweedfs-disks-patch.yaml.tftpl", {
      encryption_key = random_password.seaweedfs_disk_encryption_key.result
    }),
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/nvme1n1"
          image = "factory.talos.dev/installer/701de97a42a3f87a071189c07cf8644fc67b28aed056e3546f1ecbe8a232279a:v1.13.9"
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
