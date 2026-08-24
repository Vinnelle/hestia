locals {
  policied_namespaces = toset([
    "auth",
    "backup",
    "dns",
    "files",
    "forge",
    "miniflux",
    "monke-academy",
    "proxy",
    "registry",
    "searxng",
    "storage",
    "vin-moe",
    "vinnel-cloud",
  ])

  network_policy_ingress_from = {
    storage = ["backup", "files", "forge"]
  }

  network_policy_egress_to = {
    backup = [{ namespace = "storage", ports = [8333] }]
    files  = [{ namespace = "storage", ports = [8333] }]
    forge  = [{ namespace = "storage", ports = [8333] }]
  }
}

module "network_policy" {
  source = "./modules/network-policy"

  for_each = local.policied_namespaces

  depends_on = [
    helm_release.cilium,
    kubernetes_namespace_v1.auth,
    kubernetes_namespace_v1.backup,
    kubernetes_namespace_v1.dns,
    kubernetes_namespace_v1.files,
    kubernetes_namespace_v1.forge,
    kubernetes_namespace_v1.miniflux,
    kubernetes_namespace_v1.monke_academy,
    kubernetes_namespace_v1.proxy,
    kubernetes_namespace_v1.registry,
    kubernetes_namespace_v1.searxng,
    kubernetes_namespace_v1.storage,
    kubernetes_namespace_v1.vin_moe,
    kubernetes_namespace_v1.vinnel_cloud,
  ]

  namespace           = each.key
  telemetry_namespace = kubernetes_namespace_v1.observability.metadata[0].name
  ingress_from        = lookup(local.network_policy_ingress_from, each.key, [])
  egress_to           = lookup(local.network_policy_egress_to, each.key, [])
}
