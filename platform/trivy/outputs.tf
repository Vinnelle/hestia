output "release_id" {
  description = "Trivy operator Helm release ID; reading it orders dependents after the install"
  value       = helm_release.trivy_operator.id
}
