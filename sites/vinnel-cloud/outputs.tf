output "namespace" {
  description = "Namespace the site runs in"
  value       = kubernetes_namespace_v1.vinnel_cloud.metadata[0].name
}

output "registry_secret_name" {
  description = "Name of the dockerconfigjson Secret pulling images into the site's namespace"
  value       = kubernetes_secret_v1.registry_dockerconfig_vinnel_cloud.metadata[0].name
}

output "service_name" {
  description = "Name of the Service fronting the site's Deployment"
  value       = module.vinnel_cloud_site.service_name
}
