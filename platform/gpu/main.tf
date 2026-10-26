resource "kubernetes_runtime_class_v1" "nvidia" {
  metadata {
    name = "nvidia"
  }
  handler = "nvidia"
}

resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.20.1"
  namespace  = var.namespace
  wait       = false

  values = [
    yamlencode({
      runtimeClassName = kubernetes_runtime_class_v1.nvidia.metadata[0].name
    })
  ]
}

resource "kubernetes_config_map_v1" "dcgm_counters" {
  metadata {
    name      = "dcgm-counters"
    namespace = var.namespace
  }

  data = {
    "counters.csv" = file("${path.module}/dcgm-counters.csv")
  }
}

resource "helm_release" "dcgm_exporter" {
  name       = "dcgm-exporter"
  repository = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart      = "dcgm-exporter"
  version    = "4.8.4"
  namespace  = var.namespace
  wait       = false

  values = [
    yamlencode({
      runtimeClassName = kubernetes_runtime_class_v1.nvidia.metadata[0].name
      arguments        = ["-f", "/etc/dcgm-exporter/counters.csv"]
      serviceMonitor   = { enabled = false }
      service = {
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "9400"
        }
      }
      securityContext = {
        runAsNonRoot             = true
        runAsUser                = 1000
        allowPrivilegeEscalation = false
        capabilities = {
          add  = []
          drop = ["ALL"]
        }
      }
      extraEnv = [
        { name = "NVIDIA_VISIBLE_DEVICES", value = "all" },
      ]
      extraConfigMapVolumes = [
        { name = "counters", configMap = { name = kubernetes_config_map_v1.dcgm_counters.metadata[0].name } },
      ]
      extraVolumeMounts = [
        { name = "counters", mountPath = "/etc/dcgm-exporter/counters.csv", subPath = "counters.csv" },
      ]
      resources = {
        requests = { cpu = "20m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
    })
  ]
}
