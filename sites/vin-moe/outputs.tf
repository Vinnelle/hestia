output "namespace" {
  description = "Namespace the site runs in"
  value       = kubernetes_namespace_v1.vin_moe.metadata[0].name
}

output "registry_secret_name" {
  description = "Name of the dockerconfigjson Secret pulling images into the site's namespace"
  value       = kubernetes_secret_v1.registry_dockerconfig_vin_moe.metadata[0].name
}

output "service_name" {
  description = "Name of the Service fronting the site's Deployment"
  value       = module.vin_moe_site.service_name
}
