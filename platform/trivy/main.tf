resource "helm_release" "trivy_operator" {
  name       = "trivy-operator"
  repository = "https://aquasecurity.github.io/helm-charts"
  chart      = "trivy-operator"
  version    = "0.36.0"
  namespace  = var.namespace

  values = [
    file("${path.module}/../helm-values/trivy-operator/values.yaml")
  ]
}

module "vpa" {
  source = "../../platform/vpa/resource"

  depends_on = [helm_release.trivy_operator]

  name        = "trivy-operator"
  namespace   = var.namespace
  target_kind = "Deployment"
  target_name = "trivy-operator"
  update_mode = "Auto"
  container_policies = [
    { container_name = "trivy-operator", min_memory = "64Mi", max_memory = "512Mi" },
  ]
}

resource "signoz_rule" "critical_vulnerability_found" {
  depends_on     = [helm_release.trivy_operator]
  alert          = "CriticalVulnerabilityFound"
  alert_type     = "METRIC_BASED_ALERT"
  rule_type      = "promql_rule"
  schema_version = "v2alpha1"
  description    = "A running workload has a fixable critical CVE — trivy-operator reports it against the image it is running"

  condition = {
    composite_query = {
      panel_type = "graph"
      query_type = "promql"
      queries = [{
        promql = {
          type = "promql"
          spec = {
            name  = "A"
            query = "sum(trivy_image_vulnerabilities{severity=\"Critical\"})"
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
          channels   = var.signoz_alert_channels
        }]
      }
    }
  }

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "1h"
        frequency   = "15m"
      }
    }
  }

  notification_settings = var.signoz_notification_settings
}

resource "signoz_rule" "exposed_secret_found" {
  depends_on     = [helm_release.trivy_operator]
  alert          = "ExposedSecretFound"
  alert_type     = "METRIC_BASED_ALERT"
  rule_type      = "promql_rule"
  schema_version = "v2alpha1"
  description    = "A credential is baked into a running image — trivy-operator found it in the image layers, not in a Secret"

  condition = {
    composite_query = {
      panel_type = "graph"
      query_type = "promql"
      queries = [{
        promql = {
          type = "promql"
          spec = {
            name  = "A"
            query = "sum(trivy_image_exposedsecrets)"
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
          channels   = var.signoz_alert_channels
        }]
      }
    }
  }

  evaluation = {
    rolling = {
      kind = "rolling"
      spec = {
        eval_window = "1h"
        frequency   = "15m"
      }
    }
  }

  notification_settings = var.signoz_notification_settings
}
