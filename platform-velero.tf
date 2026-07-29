resource "kubernetes_namespace_v1" "velero" {
  metadata {
    name = "velero"
  }
}

resource "kubernetes_secret_v1" "velero_s3_credentials" {
  metadata {
    name      = "velero-s3-credentials"
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
  }

  data = {
    cloud = <<-EOT
    [default]
    aws_access_key_id=${var.s3_backup_access_key}
    aws_secret_access_key=${var.s3_backup_secret_key}
    EOT
  }
}

# The release exists in the cluster but had dropped out of state, so every apply
# planned it as a create and Helm refused with "cannot re-use a name that is
# still in use". Adopting it back is the non-destructive fix: uninstalling to let
# Terraform recreate it would tear down the backup controller.
import {
  to = helm_release.velero
  id = "velero/velero"
}

resource "helm_release" "velero" {
  depends_on = [kubectl_manifest.snapshot_controller, kubectl_manifest.ceph_block_snapshot_class]

  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = "12.1.0"
  namespace  = kubernetes_namespace_v1.velero.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/velero/values.yaml.tftpl", {
      s3_backup_endpoint = var.s3_backup_endpoint
    })
  ]
}
