terraform {
  required_version = ">= 1.9.0"
}

locals {
  rendered = yamldecode(templatefile("${path.module}/../../modules/network-policy/cilium-network-policy.yaml.tftpl", {
    namespace           = "files"
    telemetry_namespace = "observability"
    ingress_from        = ["forge"]
    egress_to           = [{ namespace = "storage", ports = [8333] }]
  }))
}

output "rendered" {
  value = local.rendered
}
