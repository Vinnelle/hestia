resource "helm_release" "kanister" {
  name       = "kanister"
  repository = "https://charts.kanister.io"
  chart      = "kanister-operator"
  version    = "0.118.0"
  namespace  = var.namespace
}

resource "kubectl_manifest" "kanister_s3_profile" {
  depends_on = [helm_release.kanister]

  yaml_body = yamlencode({
    apiVersion = "cr.kanister.io/v1alpha1"
    kind       = "Profile"
    metadata = {
      name      = "s3-profile"
      namespace = var.namespace
    }
    location = {
      type     = "s3Compliant"
      bucket   = "gaia-backups"
      endpoint = "https://${var.s3_backup_endpoint}"
      prefix   = "kanister"
      region   = "auto"
    }
    credential = {
      type = "keyPair"
      keyPair = {
        idField     = "access_key"
        secretField = "secret_key"
        secret = {
          apiVersion = "v1"
          kind       = "Secret"
          name       = var.s3_credentials_secret_name
          namespace  = var.namespace
        }
      }
    }
  })
}
