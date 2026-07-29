
resource "kubernetes_namespace_v1" "backup" {
  metadata {
    name = "backup"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "kubernetes_secret_v1" "s3_backup_credentials" {
  metadata {
    name      = "s3-backup-credentials"
    namespace = kubernetes_namespace_v1.backup.metadata[0].name
  }

  data = {
    access_key      = var.s3_backup_access_key
    secret_key      = var.s3_backup_secret_key
    restic_password = var.backup_encryption_password
  }
}