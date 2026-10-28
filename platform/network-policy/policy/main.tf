resource "kubectl_manifest" "this" {
  yaml_body = templatefile("${path.module}/cilium-network-policy.yaml.tftpl", {
    namespace           = var.namespace
    telemetry_namespace = var.telemetry_namespace
    ingress_from        = var.ingress_from
    egress_to           = var.egress_to
    egress_telemetry    = var.egress_telemetry
    egress_world_ports  = var.egress_world_ports
    egress_entities     = var.egress_entities
    egress_fqdns        = var.egress_fqdns
  })
}
