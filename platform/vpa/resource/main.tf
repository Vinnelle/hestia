resource "kubectl_manifest" "this" {
  yaml_body = templatefile("${path.module}/vpa.yaml.tftpl", {
    name               = var.name
    namespace          = var.namespace
    target_kind        = var.target_kind
    target_name        = var.target_name
    update_mode        = var.update_mode
    container_policies = var.container_policies
  })
}
