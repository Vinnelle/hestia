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

import {
  to = helm_release.velero
  id = "velero/velero"
}

resource "helm_release" "velero" {
  depends_on = [kubectl_manifest.snapshot_controller]

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
