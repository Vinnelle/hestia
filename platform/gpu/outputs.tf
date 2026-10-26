output "runtime_class_name" {
  description = "RuntimeClass GPU pods set so containerd starts them with the NVIDIA container runtime"
  value       = kubernetes_runtime_class_v1.nvidia.metadata[0].name
}
