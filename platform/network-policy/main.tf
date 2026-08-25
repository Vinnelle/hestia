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
    storage        = ["backup", "files", "forge"]
    "vinnel-cloud" = ["vin-moe"]
  }

  network_policy_egress_to = {
    backup         = [{ namespace = "storage", ports = [8333] }]
    files          = [{ namespace = "storage", ports = [8333] }]
    forge          = [{ namespace = "storage", ports = [8333] }]
    "vin-moe"      = [{ namespace = "vinnel-cloud", ports = [8080] }]
    "vinnel-cloud" = [{ namespace = "games", ports = [8080] }]
  }
}

module "network_policy" {
  source = "./policy"

  for_each = local.policied_namespaces

  namespace           = each.key
  telemetry_namespace = var.telemetry_namespace
  ingress_from        = lookup(local.network_policy_ingress_from, each.key, [])
  egress_to           = lookup(local.network_policy_egress_to, each.key, [])
}
