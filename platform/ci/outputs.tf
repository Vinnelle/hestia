output "ci_kubeconfig" {
  description = "Namespace-scoped kubeconfig for GitHub Actions (KUBECONFIG secret)."
  sensitive   = true
  value       = local.ci_kubeconfig
}
