terraform {
  required_version = ">= 1.9.0"
}

locals {
  rendered = yamldecode(templatefile("${path.module}/../../platform/network-policy/policy/cilium-network-policy.yaml.tftpl", {
    namespace           = "files"
    telemetry_namespace = "observability"
    ingress_from        = ["forge"]
    egress_to           = [{ namespace = "storage", ports = [8333] }]
    egress_telemetry    = true
    egress_world_ports  = []
    egress_entities     = ["host", "remote-node", "kube-apiserver"]
    egress_fqdns        = null
  }))

  rendered_fqdns = yamldecode(templatefile("${path.module}/../../platform/network-policy/policy/cilium-network-policy.yaml.tftpl", {
    namespace           = "backup"
    telemetry_namespace = "observability"
    ingress_from        = []
    egress_to           = [{ namespace = "storage", ports = [8333] }]
    egress_telemetry    = true
    egress_world_ports  = []
    egress_entities     = ["host", "remote-node", "kube-apiserver"]
    egress_fqdns        = ["de-fra-1.linodeobjects.com"]
  }))

  rendered_no_egress = yamldecode(templatefile("${path.module}/../../platform/network-policy/policy/cilium-network-policy.yaml.tftpl", {
    namespace           = "vin-moe"
    telemetry_namespace = "observability"
    ingress_from        = []
    egress_to           = []
    egress_telemetry    = true
    egress_world_ports  = []
    egress_entities     = ["host", "remote-node", "kube-apiserver"]
    egress_fqdns        = []
  }))

  rendered_world_ports = yamldecode(templatefile("${path.module}/../../platform/network-policy/policy/cilium-network-policy.yaml.tftpl", {
    namespace           = "bots"
    telemetry_namespace = "observability"
    ingress_from        = []
    egress_to           = [{ namespace = "llm", ports = [8080] }]
    egress_telemetry    = false
    egress_world_ports  = [443]
    egress_entities     = []
    egress_fqdns        = []
  }))
}

output "rendered" {
  value = local.rendered
}

output "rendered_fqdns" {
  value = local.rendered_fqdns
}

output "rendered_no_egress" {
  value = local.rendered_no_egress
}

output "rendered_world_ports" {
  value = local.rendered_world_ports
}
