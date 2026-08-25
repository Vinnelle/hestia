resource "kubectl_manifest" "this" {
  yaml_body = templatefile("${path.module}/cilium-network-policy.yaml.tftpl", {
    namespace           = var.namespace
    telemetry_namespace = var.telemetry_namespace
    ingress_from        = var.ingress_from
    egress_to           = var.egress_to
  })
}
