
resource "helm_release" "signoz" {
  name       = "signoz"
  repository = "https://charts.signoz.io"
  chart      = "signoz"
  version    = "0.134.0"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    file("${path.module}/helm-values/signoz/values.yaml")
  ]
}

resource "helm_release" "k8s_infra" {
  name       = "k8s-infra"
  repository = "https://charts.signoz.io"
  chart      = "k8s-infra"
  version    = "0.16.0"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name

  values = [
    templatefile("${path.module}/helm-values/k8s-infra/values.yaml.tftpl", {
      monitoring_namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
      cluster_name         = var.cluster_name
    })
  ]

  depends_on = [helm_release.signoz]
}

resource "cloudflare_dns_record" "signoz_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "signoz.vinnel.cloud"
  type    = "A"
  content = var.node_ip
  ttl     = 1
  proxied = true
}

locals {
  signoz_alert_channels = ["ntfy", "slack"]

  signoz_notification_settings = {
    group_by = ["alertname"]
    renotify = {
      enabled      = true
      alert_states = ["firing"]
      interval     = "4h"
    }
  }
}

resource "signoz_rule" "backup_job_failed" {
  depends_on     = [helm_release.signoz]
  alert          = "BackupJobFailed"
  alert_type     = "METRIC_BASED_ALERT"
  rule_type      = "promql_rule"
  schema_version = "v2alpha1"
  description    = "pv-backup CronJob has a failed run — last night's snapshot did not complete"

  condition = {
    composite_query = {
      panel_type = "graph"
      query_type = "promql"
      queries = [{
        promql = {
          type = "promql"
          spec = {
            name  = "A"
            query = "max(kube_job_status_failed{namespace=\"backup\"})"
          }
        }
      }]
    }
    selected_query_name = "A"
    thresholds = {
      basic = {
        kind = "basic"
        spec = [{
          name       = "critical"
          op         = "above"
          match_type = "at_least_once"
          target     = 0
          channels   = local.signoz_alert_channels
        }]
      }
    }
  }

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "1m"
        frequency   = "1m"
      }
    }
  }

  notification_settings = local.signoz_notification_settings
}

resource "signoz_rule" "node_not_ready" {
  depends_on     = [helm_release.signoz]
  alert          = "NodeNotReady"
  alert_type     = "METRIC_BASED_ALERT"
  rule_type      = "promql_rule"
  schema_version = "v2alpha1"
  description    = "Kubernetes reports the node NotReady"

  condition = {
    composite_query = {
      panel_type = "graph"
      query_type = "promql"
      queries = [{
        promql = {
          type = "promql"
          spec = {
            name  = "A"
            query = "min(kube_node_status_condition{condition=\"Ready\",status=\"true\"})"
          }
        }
      }]
    }
    selected_query_name = "A"
    thresholds = {
      basic = {
        kind = "basic"
        spec = [{
          name       = "critical"
          op         = "below"
          match_type = "at_least_once"
          target     = 1
          channels   = local.signoz_alert_channels
        }]
      }
    }
  }

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "5m"
        frequency   = "1m"
      }
    }
  }

  notification_settings = local.signoz_notification_settings
}

resource "signoz_rule" "pvc_almost_full" {
  depends_on     = [helm_release.signoz]
  alert          = "PVCAlmostFull"
  alert_type     = "METRIC_BASED_ALERT"
  rule_type      = "promql_rule"
  schema_version = "v2alpha1"
  description    = "PVC is over 85% full"

  condition = {
    composite_query = {
      panel_type = "graph"
      query_type = "promql"
      queries = [{
        promql = {
          type = "promql"
          spec = {
            name  = "A"
            query = "max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes)"
          }
        }
      }]
    }
    selected_query_name = "A"
    thresholds = {
      basic = {
        kind = "basic"
        spec = [{
          name       = "critical"
          op         = "above"
          match_type = "at_least_once"
          target     = 0.85
          channels   = local.signoz_alert_channels
        }]
      }
    }
  }

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "15m"
        frequency   = "1m"
      }
    }
  }

  notification_settings = local.signoz_notification_settings
}

resource "signoz_rule" "certificate_expiring_soon" {
  depends_on     = [helm_release.signoz]
  alert          = "CertificateExpiringSoon"
  alert_type     = "METRIC_BASED_ALERT"
  rule_type      = "promql_rule"
  schema_version = "v2alpha1"
  description    = "Certificate expires in under 14 days — ACME renewal is likely stuck"

  condition = {
    composite_query = {
      panel_type = "graph"
      query_type = "promql"
      queries = [{
        promql = {
          type = "promql"
          spec = {
            name  = "A"
            query = "min by (namespace, name) (certmanager_certificate_expiration_timestamp_seconds) - time()"
          }
        }
      }]
    }
    selected_query_name = "A"
    thresholds = {
      basic = {
        kind = "basic"
        spec = [{
          name       = "critical"
          op         = "below"
          match_type = "at_least_once"
          target     = 1209600
          channels   = local.signoz_alert_channels
        }]
      }
    }
  }

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "1h"
        frequency   = "1m"
      }
    }
  }

  notification_settings = local.signoz_notification_settings
}

resource "signoz_rule" "workload_degraded" {
  depends_on     = [helm_release.signoz]
  alert          = "WorkloadDegraded"
  alert_type     = "METRIC_BASED_ALERT"
  rule_type      = "promql_rule"
  schema_version = "v2alpha1"
  description    = "A deployment or statefulset has been running below desired replicas for 15m (crashloop, image pull failure, stuck rollout)"

  condition = {
    composite_query = {
      panel_type = "graph"
      query_type = "promql"
      queries = [{
        promql = {
          type = "promql"
          spec = {
            name  = "A"
            query = "(kube_deployment_status_replicas_available / clamp_min(kube_deployment_spec_replicas, 1)) or (kube_statefulset_status_replicas_ready / clamp_min(kube_statefulset_replicas, 1))"
          }
        }
      }]
    }
    selected_query_name = "A"
    thresholds = {
      basic = {
        kind = "basic"
        spec = [{
          name       = "critical"
          op         = "below"
          match_type = "at_least_once"
          target     = 1
          channels   = local.signoz_alert_channels
        }]
      }
    }
  }

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "15m"
        frequency   = "1m"
      }
    }
  }

  notification_settings = local.signoz_notification_settings
}

resource "kubernetes_ingress_v1" "signoz_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx, helm_release.signoz]
  metadata {
    name      = "signoz-vinnel-cloud"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["signoz.vinnel.cloud"]
      secret_name = "signoz-vinnel-cloud-tls"
    }

    rule {
      host = "signoz.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "signoz"
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}
