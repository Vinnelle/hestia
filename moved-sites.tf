moved {
  from = cloudflare_dns_record.vin_moe_apex
  to   = module.vin_moe_site.cloudflare_dns_record.apex
}

moved {
  from = cloudflare_ruleset.vin_moe_cache
  to   = module.vin_moe_site.cloudflare_ruleset.cache
}

moved {
  from = kubectl_manifest.letsencrypt_prod_vin_moe
  to   = module.vin_moe_site.kubectl_manifest.letsencrypt
}

moved {
  from = kubernetes_pod_disruption_budget_v1.vin_moe_site
  to   = module.vin_moe_site.kubernetes_pod_disruption_budget_v1.this
}

moved {
  from = kubernetes_deployment_v1.vin_moe_site
  to   = module.vin_moe_site.kubernetes_deployment_v1.this
}

moved {
  from = kubectl_manifest.vin_moe_site_vpa
  to   = module.vin_moe_site.module.vpa.kubectl_manifest.this
}

moved {
  from = kubernetes_service_v1.vin_moe_site
  to   = module.vin_moe_site.kubernetes_service_v1.this
}

moved {
  from = kubernetes_ingress_v1.vin_moe_site
  to   = module.vin_moe_site.kubernetes_ingress_v1.this
}

moved {
  from = cloudflare_dns_record.monke_academy_apex
  to   = module.monke_academy_site.cloudflare_dns_record.apex
}

moved {
  from = cloudflare_ruleset.monke_academy_cache
  to   = module.monke_academy_site.cloudflare_ruleset.cache
}

moved {
  from = kubectl_manifest.letsencrypt_prod_monke_academy
  to   = module.monke_academy_site.kubectl_manifest.letsencrypt
}

moved {
  from = kubernetes_pod_disruption_budget_v1.monke_academy_site
  to   = module.monke_academy_site.kubernetes_pod_disruption_budget_v1.this
}

moved {
  from = kubernetes_deployment_v1.monke_academy_site
  to   = module.monke_academy_site.kubernetes_deployment_v1.this
}

moved {
  from = kubectl_manifest.monke_academy_site_vpa
  to   = module.monke_academy_site.module.vpa.kubectl_manifest.this
}

moved {
  from = kubernetes_service_v1.monke_academy_site
  to   = module.monke_academy_site.kubernetes_service_v1.this
}

moved {
  from = kubernetes_ingress_v1.monke_academy_site
  to   = module.monke_academy_site.kubernetes_ingress_v1.this
}

moved {
  from = cloudflare_dns_record.vinnel_cloud_apex
  to   = module.vinnel_cloud_site.cloudflare_dns_record.apex
}

moved {
  from = cloudflare_ruleset.vinnel_cloud_cache
  to   = module.vinnel_cloud_site.cloudflare_ruleset.cache
}

moved {
  from = kubectl_manifest.letsencrypt_prod_vinnel_cloud
  to   = module.vinnel_cloud_site.kubectl_manifest.letsencrypt
}

moved {
  from = kubernetes_pod_disruption_budget_v1.vinnel_cloud_site
  to   = module.vinnel_cloud_site.kubernetes_pod_disruption_budget_v1.this
}

moved {
  from = kubernetes_deployment_v1.vinnel_cloud_site
  to   = module.vinnel_cloud_site.kubernetes_deployment_v1.this
}

moved {
  from = kubectl_manifest.vinnel_cloud_site_vpa
  to   = module.vinnel_cloud_site.module.vpa.kubectl_manifest.this
}

moved {
  from = kubernetes_service_v1.vinnel_cloud_site
  to   = module.vinnel_cloud_site.kubernetes_service_v1.this
}

moved {
  from = kubernetes_ingress_v1.vinnel_cloud_site
  to   = module.vinnel_cloud_site.kubernetes_ingress_v1.this
}
