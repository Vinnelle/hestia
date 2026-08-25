resource "aws_s3_bucket" "velero" {
  provider = aws.mega_s4
  bucket   = "velero"
}

resource "kubernetes_secret_v1" "velero_s3_credentials" {
  metadata {
    name      = "velero-s3-credentials"
    namespace = var.namespace
  }

  data = {
    cloud = <<-EOT
    [default]
    aws_access_key_id=${var.mega_s4_access_key}
    aws_secret_access_key=${var.mega_s4_secret_key}

    [seaweedfs]
    aws_access_key_id=${var.seaweedfs_s3_access_key}
    aws_secret_access_key=${var.seaweedfs_s3_secret_key}
    EOT
  }
}

resource "helm_release" "velero" {
  depends_on = [aws_s3_bucket.velero]

  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = "12.1.0"
  namespace  = var.namespace

  values = [
    templatefile("${path.module}/../helm-values/velero/values.yaml.tftpl", {
      mega_s4_endpoint_domain = var.mega_s4_endpoint_domain
    })
  ]
}
