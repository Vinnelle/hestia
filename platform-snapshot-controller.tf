resource "kubectl_manifest" "snapshot_controller" {
  for_each  = fileset("${path.module}/platform/manifests/snapshot-controller", "*.yaml")
  yaml_body = file("${path.module}/platform/manifests/snapshot-controller/${each.value}")
}
