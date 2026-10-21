output "namespace" {
  description = "Namespace holding cluster plumbing workloads"
  value       = kubernetes_namespace_v1.platform.metadata[0].name
}

output "zone_id_vin_moe" {
  description = "Cloudflare zone ID for vin.moe"
  value       = data.cloudflare_zone.vin_moe.id
}

output "zone_id_vinnel_cloud" {
  description = "Cloudflare zone ID for vinnel.cloud"
  value       = data.cloudflare_zone.vinnel_cloud.id
}

output "ingress_class_name" {
  description = "IngressClass served by ingress-nginx; reading it orders an Ingress after the controller install"
  value       = "nginx"

  depends_on = [helm_release.ingress_nginx]
}
