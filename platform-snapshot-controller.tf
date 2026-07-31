resource "kubectl_manifest" "snapshot_controller" {
  for_each  = fileset("${path.module}/manifests/snapshot-controller", "*.yaml")
  yaml_body = file("${path.module}/manifests/snapshot-controller/${each.value}")
}
