locals {
  policied_namespaces = toset([
    "auth",
    "dns",
    "files",
    "forge",
    "matrix",
    "miniflux",
    "proxy",
    "registry",
    "searxng",
    "storage",
    "vin-moe",
    "vinnel-cloud",
  ])

  network_policy_ingress_from = {
    storage        = ["files", "forge"]
    "vinnel-cloud" = ["vin-moe"]
  }

  network_policy_egress_fqdns = {
    matrix    = []
    storage   = []
    "vin-moe" = []
  }

  network_policy_egress_to = {
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
  egress_fqdns        = lookup(local.network_policy_egress_fqdns, each.key, null)
}

resource "kubectl_manifest" "deny_relay_to_pods" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2"
    kind       = "CiliumClusterwideNetworkPolicy"
    metadata = {
      name = "deny-relay-to-pods"
    }
    spec = {
      endpointSelector = {}
      enableDefaultDeny = {
        ingress = false
        egress  = false
      }
      ingressDeny = [{
        fromCIDR = ["${var.relay_address}/32"]
      }]
    }
  })
}
