removed {
  from = module.platform_velero

  lifecycle {
    destroy = false
  }
}

moved {
  from = module.observability_signoz.kubernetes_namespace_v1.observability
  to   = module.observability_grafana.kubernetes_namespace_v1.observability
}

moved {
  from = module.observability_signoz.cloudflare_dns_record.signoz_vinnel_cloud
  to   = module.observability_grafana.cloudflare_dns_record.grafana_vinnel_cloud
}
