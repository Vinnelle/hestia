variable "namespace" {
  description = "Privileged namespace the device plugin's DaemonSet runs in; it mounts the kubelet's device-plugin socket directory from the host"
  type        = string
}
