locals {
  policied_namespaces = toset([
    "auth",
    "automations",
    "dns",
    "files",
    "forge",
    "llm",
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
    automations    = ["forge"]
    llm            = ["automations"]
    storage        = ["files", "forge"]
    "vinnel-cloud" = ["vin-moe"]
  }

  network_policy_egress_fqdns = {
    automations = ["api.resend.com"]
    llm         = ["huggingface.co", "**.hf.co"]
    matrix      = []
    storage     = []
    "vin-moe"   = []
  }

  network_policy_egress_to = {
    automations = [{ namespace = "llm", ports = [8080] }]
    files       = [{ namespace = "storage", ports = [8333] }]
    forge = [
      { namespace = "storage", ports = [8333] },
      { namespace = "automations", ports = [8080] },
    ]
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
