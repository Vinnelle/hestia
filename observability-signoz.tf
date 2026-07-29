
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
      node_ip              = var.node_ip
    })
  ]

  depends_on = [helm_release.signoz]
}

resource "kubernetes_cluster_role_v1" "otel_agent_metrics" {
  metadata {
    name = "k8s-infra-otel-agent-metrics"
  }

  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes/metrics"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "otel_agent_metrics" {
  metadata {
    name = "k8s-infra-otel-agent-metrics"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.otel_agent_metrics.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "k8s-infra-otel-agent"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
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
            query = "max({\"k8s.job.failed_pods\",\"k8s.namespace.name\"=\"backup\"})"
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
            query = "min({\"k8s.node.condition_ready\"})"
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
            query = "max by (\"k8s.namespace.name\",\"k8s.persistentvolumeclaim.name\") (1 - {\"k8s.volume.available\"} / {\"k8s.volume.capacity\"})"
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
            query = "({\"k8s.deployment.available\"} / clamp_min({\"k8s.deployment.desired\"}, 1)) or ({\"k8s.statefulset.ready_pods\"} / clamp_min({\"k8s.statefulset.desired_pods\"}, 1))"
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

# Web UI: behind Authelia and framed by admin.vinnel.cloud. Split from /api below,
# which must stay open — the signoz and restapi providers in providers.tf reach
# https://signoz.vinnel.cloud/api/v1 from Terraform Cloud, outside the cluster, so
# a forward-auth redirect there would break every dashboard and alert rule apply.
# The SPA's own XHR to /api also lands on the open Ingress; SigNoz's API-key auth
# is the gate for that path, exactly as it is today.
resource "kubernetes_ingress_v1" "signoz_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx, helm_release.signoz]
  metadata {
    name      = "signoz-vinnel-cloud"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = merge(local.admin_framed_service_annotations, {
      "cert-manager.io/cluster-issuer" = local.vinnel_cloud_cluster_issuer
    })
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

# API plane: Terraform Cloud providers and the SPA's own XHR. No forward-auth and
# no Sec-Fetch bounce. cert-manager.io/cluster-issuer is deliberately absent —
# signoz_vinnel_cloud above owns signoz-vinnel-cloud-tls, and two Ingresses
# requesting the same secret for the same host would leave two Certificates
# contending over it.
resource "kubernetes_ingress_v1" "signoz_api_vinnel_cloud" {
  depends_on = [helm_release.ingress_nginx, helm_release.signoz, kubernetes_ingress_v1.signoz_vinnel_cloud]
  metadata {
    name      = "signoz-api-vinnel-cloud"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
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
          path      = "/api"
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
