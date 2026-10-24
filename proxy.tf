# NetBird

module "proxy_netbird" {
  source = "./proxy/netbird"

  depends_on = [module.platform_vpa]

  zone_id                         = module.platform_core.zone_id_vinnel_cloud
  node_ip                         = var.node_ip
  relay_ip                        = module.platform_relay.ipv4
  cluster_issuer                  = local.vinnel_cloud_cluster_issuer
  ingress_class_name              = module.platform_core.ingress_class_name
  admin_frame_service_annotations = local.admin_framed_service_annotations["proxy"]
  dashboard_oidc_client_secret    = module.identity_authelia.netbird_dashboard_oidc_client_secret
  adguard_peer_ids                = module.adguard.peer_ids
}
