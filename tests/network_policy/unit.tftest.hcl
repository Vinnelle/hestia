# The policy is default-deny: everything it fails to render is silently dropped
# traffic on a cluster whose recovery path is manual. These asserts cover the
# three renderings that break quietly rather than loudly — an endpointSelector
# that selects nothing (policy present, nothing enforced), a missing DNS leg
# (every name lookup in the namespace times out), and a port list that lands on
# the wrong egress rule (which would clamp same-namespace traffic to that one
# port instead of widening it). See gaia/CLAUDE.md's platform/network-policy/policy row.
run "endpoint_selector_selects_the_whole_namespace" {
  command = plan

  assert {
    condition     = output.rendered.spec.endpointSelector == {}
    error_message = "endpointSelector must render as an empty object — anything else selects a subset of the namespace and leaves the rest unenforced"
  }
}

run "dns_egress_survives_default_deny" {
  command = plan

  assert {
    condition = anytrue([
      for rule in output.rendered.spec.egress :
      try(rule.toEndpoints[0].matchLabels["k8s:k8s-app"], null) == "kube-dns" &&
      try([for p in rule.toPorts[0].ports : p.protocol], []) == ["UDP", "TCP"]
    ])
    error_message = "egress must allow kube-dns on 53/UDP and 53/TCP — without it every lookup in the namespace fails closed"
  }
}

run "cross_namespace_exception_is_its_own_rule" {
  command = plan

  assert {
    condition = anytrue([
      for rule in output.rendered.spec.egress :
      try(rule.toEndpoints[0].matchLabels["k8s:io.kubernetes.pod.namespace"], null) == "storage" &&
      try(rule.toPorts[0].ports[0].port, null) == "8333"
    ])
    error_message = "egress_to must render its own rule with the port quoted as a string — Cilium rejects a numeric port"
  }
}

run "same_namespace_egress_is_not_port_clamped" {
  command = plan

  assert {
    condition = anytrue([
      for rule in output.rendered.spec.egress :
      contains([for e in try(rule.toEndpoints, []) : e.matchLabels["k8s:io.kubernetes.pod.namespace"]], "files") &&
      !contains(keys(rule), "toPorts")
    ])
    error_message = "the same-namespace egress rule must carry no toPorts — attaching one restricts intra-namespace traffic to those ports"
  }
}

run "ingress_from_namespaces_are_allowed" {
  command = plan

  assert {
    condition = anytrue([
      for rule in output.rendered.spec.ingress :
      contains([for e in try(rule.fromEndpoints, []) : e.matchLabels["k8s:io.kubernetes.pod.namespace"]], "forge")
    ])
    error_message = "ingress_from namespaces must appear in a fromEndpoints selector"
  }
}

run "world_egress_survives_when_no_fqdn_list_is_set" {
  command = plan

  assert {
    condition = anytrue([
      for rule in output.rendered.spec.egress :
      contains(try(rule.toEntities, []), "world")
    ])
    error_message = "a namespace with egress_fqdns unset must keep the `world` entity — dropping it silently cuts every outbound connection the namespace makes"
  }
}

run "fqdn_egress_replaces_world_and_keeps_dns_visible" {
  command = plan

  assert {
    condition = !anytrue([
      for rule in output.rendered_fqdns.spec.egress :
      contains(try(rule.toEntities, []), "world")
    ])
    error_message = "egress_fqdns must drop the `world` entity — leaving it in place makes the FQDN allowlist decorative"
  }

  assert {
    condition = anytrue([
      for rule in output.rendered_fqdns.spec.egress :
      try(rule.toFQDNs[0].matchPattern, null) == "s3.g.megas4.com" &&
      try(rule.toPorts[0].ports[0].port, null) == "443"
    ])
    error_message = "each egress_fqdns entry must render a toFQDNs rule on 443/TCP"
  }

  assert {
    condition = anytrue([
      for rule in output.rendered_fqdns.spec.egress :
      try(rule.toEndpoints[0].matchLabels["k8s:k8s-app"], null) == "kube-dns" &&
      try(rule.toPorts[0].rules.dns[0].matchPattern, null) == "*"
    ])
    error_message = "FQDN policy needs the DNS leg carrying an L7 dns matchPattern — without it Cilium never sees the lookup and every allowed name resolves to a denied IP"
  }
}

run "empty_fqdn_list_leaves_no_external_egress" {
  command = plan

  assert {
    condition = !anytrue([
      for rule in output.rendered_no_egress.spec.egress :
      contains(try(rule.toEntities, []), "world") || contains(keys(rule), "toFQDNs")
    ])
    error_message = "an empty egress_fqdns list must render neither `world` nor a toFQDNs rule — that is the whole point of the empty list"
  }

  assert {
    condition = anytrue([
      for rule in output.rendered_no_egress.spec.egress :
      contains(try(rule.toEntities, []), "kube-apiserver")
    ])
    error_message = "dropping external egress must not drop the kube-apiserver entity with it"
  }
}
