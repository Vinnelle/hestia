# Alert rules, provisioned into Grafana's built-in alerting engine.
#
# Delivery: routed to ntfy (apps-ntfy.tf) via the default notification policy
# below. Whole-node death can't be self-reported from a single-node cluster —
# pair this with an external uptime check on the public sites.

resource "grafana_folder" "alerting" {
  title = "Alerting"
}

resource "grafana_contact_point" "ntfy" {
  name = "ntfy"

  webhook {
    url                       = "https://ntfy.vinnel.cloud/hestia-alerts"
    authorization_scheme      = "Bearer"
    authorization_credentials = local.ntfy_publisher_token

    headers = {
      "Title"    = "{{ .Title }}"
      "Priority" = "{{ if eq .Status \"firing\" }}high{{ else }}default{{ end }}"
      "Tags"     = "{{ if eq .Status \"firing\" }}rotating_light{{ else }}white_check_mark{{ end }}"
    }

    # ntfy's JSON publish API only exists at the root URL and requires a
    # "topic" field; posting straight to the topic URL treats the body as the
    # raw message text instead, so trim it down to just that.
    payload {
      template = "{{ .Message }}"
    }
  }
}

resource "grafana_notification_policy" "default" {
  contact_point = grafana_contact_point.ntfy.name
  group_by      = ["alertname"]

  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"
}

resource "grafana_rule_group" "infrastructure" {
  name             = "infrastructure"
  folder_uid       = grafana_folder.alerting.uid
  interval_seconds = 60

  rule {
    name           = "BackupJobFailed"
    condition      = "C"
    for            = "0s"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "pv-backup CronJob has a failed run — last night's snapshot did not complete"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.prometheus.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId   = "A"
        expr    = "max(kube_job_status_failed{namespace=\"backup\"})"
        instant = true
        range   = false
        datasource = {
          type = "prometheus"
          uid  = grafana_data_source.prometheus.uid
        }
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "A"
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        conditions = [{
          evaluator = {
            type   = "gt"
            params = [0]
          }
        }]
      })
    }
  }

  rule {
    name           = "NodeNotReady"
    condition      = "C"
    for            = "5m"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "Kubernetes reports the node NotReady"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.prometheus.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId   = "A"
        expr    = "min(kube_node_status_condition{condition=\"Ready\",status=\"true\"})"
        instant = true
        range   = false
        datasource = {
          type = "prometheus"
          uid  = grafana_data_source.prometheus.uid
        }
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "A"
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        conditions = [{
          evaluator = {
            type   = "lt"
            params = [1]
          }
        }]
      })
    }
  }

  rule {
    name           = "PVCAlmostFull"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is over 85% full"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.prometheus.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId   = "A"
        expr    = "max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes)"
        instant = true
        range   = false
        datasource = {
          type = "prometheus"
          uid  = grafana_data_source.prometheus.uid
        }
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "A"
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        conditions = [{
          evaluator = {
            type   = "gt"
            params = [0.85]
          }
        }]
      })
    }
  }

  rule {
    name           = "CertificateExpiringSoon"
    condition      = "C"
    for            = "1h"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "Certificate {{ $labels.namespace }}/{{ $labels.name }} expires in under 14 days — ACME renewal is likely stuck"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.prometheus.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId   = "A"
        expr    = "min by (namespace, name) (certmanager_certificate_expiration_timestamp_seconds) - time()"
        instant = true
        range   = false
        datasource = {
          type = "prometheus"
          uid  = grafana_data_source.prometheus.uid
        }
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "A"
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        conditions = [{
          evaluator = {
            type   = "lt"
            params = [1209600] # 14 days in seconds
          }
        }]
      })
    }
  }

  rule {
    name           = "WorkloadDegraded"
    condition      = "C"
    for            = "15m"
    no_data_state  = "OK"
    exec_err_state = "Error"

    annotations = {
      summary = "A deployment or statefulset has been running below desired replicas for 15m (crashloop, image pull failure, stuck rollout)"
    }

    data {
      ref_id         = "A"
      datasource_uid = grafana_data_source.prometheus.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        refId   = "A"
        expr    = "(kube_deployment_status_replicas_available / clamp_min(kube_deployment_spec_replicas, 1)) or (kube_statefulset_status_replicas_ready / clamp_min(kube_statefulset_replicas, 1))"
        instant = true
        range   = false
        datasource = {
          type = "prometheus"
          uid  = grafana_data_source.prometheus.uid
        }
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 0
        to   = 0
      }
      model = jsonencode({
        refId      = "C"
        type       = "threshold"
        expression = "A"
        datasource = {
          type = "__expr__"
          uid  = "__expr__"
        }
        conditions = [{
          evaluator = {
            type   = "lt"
            params = [1]
          }
        }]
      })
    }
  }
}
