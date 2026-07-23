resource "cloudflare_r2_bucket" "backups" {
  account_id = data.cloudflare_zone.vinnel_cloud.account.id
  name       = "hestia-backups"
  location   = "WEUR"
}

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

resource "kubernetes_cron_job_v1" "pv_backup" {
  metadata {
    name      = "pv-backup"
    namespace = kubernetes_namespace_v1.backup.metadata[0].name
  }

  spec {
    schedule                      = "0 3 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        name = "pv-backup"
      }
      spec {
        template {
          metadata {
            name = "pv-backup"
          }
          spec {
            restart_policy = "OnFailure"

            container {
              name    = "backup"
              image   = "restic/restic:0.19.1"
              command = ["/bin/sh", "-c", file("${path.module}/backup/pv-backup.sh")]

              env {
                name  = "RESTIC_REPOSITORY"
                value = "s3:https://${data.cloudflare_zone.vinnel_cloud.account.id}.r2.cloudflarestorage.com/${cloudflare_r2_bucket.backups.name}/restic"
              }
              env {
                name = "RESTIC_PASSWORD"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.s3_backup_credentials.metadata[0].name
                    key  = "restic_password"
                  }
                }
              }
              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.s3_backup_credentials.metadata[0].name
                    key  = "access_key"
                  }
                }
              }
              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret_v1.s3_backup_credentials.metadata[0].name
                    key  = "secret_key"
                  }
                }
              }
              env {
                name  = "AWS_DEFAULT_REGION"
                value = "auto"
              }

              volume_mount {
                name       = "data"
                mount_path = "/data"
                read_only  = true
              }
            }

            volume {
              name = "data"
              host_path {
                path = "/opt/local-path-provisioner"
              }
            }
          }
        }
      }
    }
  }
}
