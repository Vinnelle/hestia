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
              image = "registry.k8s.io/kubectl:v1.36.4"
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
