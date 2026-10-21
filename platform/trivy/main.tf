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

resource "kubectl_manifest" "alert_rules" {
  depends_on = [helm_release.trivy_operator]

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMRule"
    metadata = {
      name      = "trivy"
      namespace = var.namespace
    }
    spec = {
      groups = [{
        name     = "trivy"
        interval = "15m"
        rules = [
          {
            alert = "CriticalVulnerabilityFound"
            expr  = "sum by (namespace, resource_name) (label_replace(trivy_image_vulnerabilities{severity=\"Critical\"}, \"namespace\", \"$1\", \"exported_namespace\", \"(.+)\")) > 0"
            for   = "1h"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "{{ $labels.namespace }}/{{ $labels.resource_name }} runs an image with a critical CVE"
              description = "trivy-operator reports it against the image the workload is running."
            }
          },
          {
            alert = "ExposedSecretFound"
            expr  = "sum by (namespace, resource_name) (label_replace(trivy_image_exposedsecrets, \"namespace\", \"$1\", \"exported_namespace\", \"(.+)\")) > 0"
            for   = "15m"
            labels = {
              severity = "critical"
            }
            annotations = {
              summary     = "{{ $labels.namespace }}/{{ $labels.resource_name }} has a credential baked into its image"
              description = "trivy-operator found it in the image layers, not in a Secret."
            }
          },
        ]
      }]
    }
  })
}
