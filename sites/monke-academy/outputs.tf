output "namespace" {
  description = "Namespace the site runs in"
  value       = kubernetes_namespace_v1.monke_academy.metadata[0].name
}

output "registry_secret_name" {
  description = "Name of the dockerconfigjson Secret pulling images into the site's namespace"
  value       = kubernetes_secret_v1.registry_dockerconfig_monke_academy.metadata[0].name
}

output "service_name" {
  description = "Name of the Service fronting the site's Deployment"
  value       = module.monke_academy_site.service_name
}
