output "release_id" {
  description = "Cilium Helm release ID; reading it orders dependents after the CNI install"
  value       = helm_release.cilium.id
}
