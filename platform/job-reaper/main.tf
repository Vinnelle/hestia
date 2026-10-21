resource "kubernetes_service_account_v1" "job_reaper" {
  metadata {
    name      = "job-reaper"
    namespace = var.namespace
  }
}

resource "kubernetes_cluster_role_v1" "job_reaper" {
  metadata {
    name = "job-reaper"
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["list", "delete"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "job_reaper" {
  metadata {
    name = "job-reaper"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.job_reaper.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.job_reaper.metadata[0].name
    namespace = kubernetes_service_account_v1.job_reaper.metadata[0].namespace
  }
}

resource "kubernetes_cron_job_v1" "job_reaper" {
  metadata {
    name      = "job-reaper"
    namespace = var.namespace
  }

  spec {
    schedule                      = "0 3 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 1

    job_template {
      metadata {}
      spec {
        template {
          metadata {}
          spec {
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account_v1.job_reaper.metadata[0].name
            container {
              name  = "reaper"
              image = "registry.k8s.io/kubectl:v1.37.1"
              args = [
                "delete",
                "jobs",
                "--all-namespaces",
                "--field-selector",
                "status.successful=1",
              ]
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_account_v1" "pod_reaper" {
  metadata {
    name      = "pod-reaper"
    namespace = var.namespace
  }
}

resource "kubernetes_cluster_role_v1" "pod_reaper" {
  metadata {
    name = "pod-reaper"
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "pod_reaper" {
  metadata {
    name = "pod-reaper"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.pod_reaper.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.pod_reaper.metadata[0].name
    namespace = kubernetes_service_account_v1.pod_reaper.metadata[0].namespace
  }
}

resource "kubernetes_cron_job_v1" "pod_reaper" {
  metadata {
    name      = "pod-reaper"
    namespace = var.namespace
  }

  spec {
    schedule                      = "*/15 * * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 1
    failed_jobs_history_limit     = 1

    job_template {
      metadata {}
      spec {
        template {
          metadata {}
          spec {
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account_v1.pod_reaper.metadata[0].name
            container {
              name    = "reaper"
              image   = "docker.io/alpine/kubectl:1.37.1@sha256:8c72f6f732ce7ef11cdb1bea25faa4f4a521872a12c89e3f40ba9edb52a4d4f2"
              command = ["sh", "-c", file("${path.module}/reap-pods.sh")]
            }
          }
        }
      }
    }
  }
}
