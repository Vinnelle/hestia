resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.node_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version = "v1.13.7"

  config_patches = [
    file("${path.module}/talos/controlplane-patch.yaml"),
    templatefile("${path.module}/talos/firewall.yaml.tftpl", {
      node_ip = var.node_ip
    }),
    yamlencode({
      machine = {
        install = {
          disk  = "/dev/nvme0n1"
          image = "factory.talos.dev/installer/fc53b0370f142f9f3c225d126416cd23bf42ef43b5039ab26da9e692b9588a40:v1.13.7"
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
