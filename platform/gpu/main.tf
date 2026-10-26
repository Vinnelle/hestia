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
