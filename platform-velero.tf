resource "kubernetes_namespace_v1" "velero" {
  metadata {
    name = "velero"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "aws_s3_bucket" "velero" {
  provider = aws.mega_s4
  bucket   = "velero"
}

resource "kubernetes_secret_v1" "velero_s3_credentials" {
  metadata {
    name      = "velero-s3-credentials"
    namespace = kubernetes_namespace_v1.velero.metadata[0].name
  }

  data = {
    cloud = <<-EOT
    [default]
    aws_access_key_id=${var.mega_s4_access_key}
    aws_secret_access_key=${var.mega_s4_secret_key}

    [seaweedfs]
    aws_access_key_id=${random_password.seaweedfs_s3_access_key.result}
    aws_secret_access_key=${random_password.seaweedfs_s3_secret_key.result}
    EOT
  }
}

import {
  to = helm_release.velero
  id = "velero/velero"
}

resource "helm_release" "velero" {
  depends_on = [kubectl_manifest.snapshot_controller, aws_s3_bucket.velero]

  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = "12.1.0"
  namespace  = kubernetes_namespace_v1.velero.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/velero/values.yaml.tftpl", {
      mega_s4_endpoint_domain = var.mega_s4_endpoint_domain
    })
  ]
}
