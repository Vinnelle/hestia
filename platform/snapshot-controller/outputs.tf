output "manifest_ids" {
  description = "Applied snapshot-controller manifest IDs; reading them orders dependents after the install"
  value       = [for m in kubectl_manifest.snapshot_controller : m.id]
}
