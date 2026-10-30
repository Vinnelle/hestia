# Grafana

module "observability_grafana" {
  source = "./observability/grafana"

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  relay_ip                        = module.platform_relay.ipv4
  node_ip                         = var.node_ip
  cluster_name                    = var.cluster_name
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["grafana"]
  alert_email                     = var.alert_email
  resend_api_key                  = var.resend_api_key
  sidecar_image                   = local.images["grafana-sidecar"]
  registry_dockerconfigjson       = module.gitlab.registry_dockerconfigjson
}

# Better Stack

module "observability_betterstack" {
  source = "./observability/betterstack"

  namespace          = module.vinnel_cloud.namespace
  zone_id            = module.platform_core.zone_id_vinnel_cloud
  relay_ip           = module.platform_relay.ipv4
  cluster_issuer     = local.vinnel_cloud_cluster_issuer
  ingress_class_name = module.platform_core.ingress_class_name
  site_service_name  = module.vinnel_cloud.service_name
}
