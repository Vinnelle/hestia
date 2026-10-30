locals {
  namespace     = kubernetes_namespace_v1.observability.metadata[0].name
  vm_sources    = jsondecode(file("${path.module}/../../platform/helm-values/victoria-metrics-k8s-stack/sources.json"))
  sidecar_image = regex("^(?P<registry>[^/]+)/(?P<repository>[^:@]+)(?::(?P<tag>[^@]+))?@sha256:(?P<sha>[0-9a-f]{64})$", var.sidecar_image)
}

resource "kubernetes_secret_v1" "registry_dockerconfig" {
  metadata {
    name      = "registry-dockerconfig"
    namespace = local.namespace
  }
  type = "kubernetes.io/dockerconfigjson"
  data = {
    ".dockerconfigjson" = var.registry_dockerconfigjson
  }
}

resource "random_password" "grafana_oidc_client_secret" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "grafana_oidc" {
  metadata {
    name      = "grafana-oidc"
    namespace = local.namespace
  }

  data = {
    client-secret = random_password.grafana_oidc_client_secret.result
  }
}

resource "kubernetes_secret_v1" "alertmanager_smtp" {
  metadata {
    name      = "alertmanager-smtp"
    namespace = local.namespace
  }

  data = {
    password = var.resend_api_key
  }
}

resource "helm_release" "victoria_metrics" {
  name       = "vm"
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-metrics-k8s-stack"
  version    = "0.96.1"
  namespace  = local.namespace
  timeout    = 900

  values = [
    templatefile("${path.module}/../../platform/helm-values/victoria-metrics-k8s-stack/values.yaml.tftpl", {
      namespace        = local.namespace
      node_ip          = var.node_ip
      cluster_name     = var.cluster_name
      alert_email      = var.alert_email
      smtp_secret_name = kubernetes_secret_v1.alertmanager_smtp.metadata[0].name
      oidc_secret_name = kubernetes_secret_v1.grafana_oidc.metadata[0].name
      pull_secret_name = kubernetes_secret_v1.registry_dockerconfig.metadata[0].name
      sidecar_registry = local.sidecar_image.registry
      sidecar_repo     = local.sidecar_image.repository
      sidecar_tag      = coalesce(local.sidecar_image.tag, "latest")
      sidecar_sha      = local.sidecar_image.sha
    }),
    yamlencode({
      defaultRules      = { sources = { for name, url in local.vm_sources.rules : name => { url = url } } }
      defaultDashboards = { sources = { for name, url in local.vm_sources.dashboards : name => { url = url } } }
    }),
  ]
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "7.5.0"
  namespace  = local.namespace
  timeout    = 600

  values = [
    file("${path.module}/../../platform/helm-values/loki/values.yaml")
  ]
}

resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.178.0"
  namespace  = local.namespace

  values = [
    templatefile("${path.module}/../../platform/helm-values/opentelemetry-collector/values.yaml.tftpl", {
      namespace = local.namespace
    })
  ]
}

resource "kubectl_manifest" "alert_rules" {
  depends_on = [helm_release.victoria_metrics]

  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMRule"
    metadata = {
      name      = "hestia"
      namespace = local.namespace
    }
    spec = {
      groups = [{
        name = "hestia"
        rules = [
          {
            alert = "CertificateExpiringSoon"
            expr  = "min by (namespace, name) (certmanager_certificate_expiration_timestamp_seconds) - time() < 14 * 86400"
            for   = "1h"
            labels = {
              severity = "critical"
            }
            annotations = {
              summary     = "Certificate {{ $labels.namespace }}/{{ $labels.name }} expires in under 14 days"
              description = "cert-manager should have renewed it 30 days out, so ACME renewal is likely stuck."
            }
          },
          {
            alert = "PVCAlmostFull"
            expr  = "max by (namespace, persistentvolumeclaim) (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.85"
            for   = "15m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary = "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is over 85% full"
            }
          },
        ]
      }]
    }
  })
}

resource "cloudflare_dns_record" "grafana_vinnel_cloud" {
  zone_id = var.zone_id
  name    = "grafana.vinnel.cloud"
  type    = "A"
  content = var.relay_ip
  ttl     = 60
  proxied = false
}

resource "kubernetes_ingress_v1" "grafana_vinnel_cloud" {
  depends_on = [helm_release.victoria_metrics]

  metadata {
    name      = "grafana-vinnel-cloud"
    namespace = local.namespace
    annotations = merge(var.admin_frame_service_annotations, {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    })
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = ["grafana.vinnel.cloud"]
      secret_name = "grafana-vinnel-cloud-tls"
    }

    rule {
      host = "grafana.vinnel.cloud"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
