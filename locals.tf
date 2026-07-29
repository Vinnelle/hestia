locals {
  vin_moe_cluster_issuer       = "letsencrypt-prod-vin-moe"
  vinnel_cloud_cluster_issuer  = "letsencrypt-prod-vinnel-cloud"
  monke_academy_cluster_issuer = "letsencrypt-prod-monke-academy"

  authelia_forward_auth_annotations = {
    "nginx.ingress.kubernetes.io/auth-url"              = "http://authelia.services.svc.cluster.local/api/authz/auth-request"
    "nginx.ingress.kubernetes.io/auth-signin"           = "https://auth.vinnel.cloud/?rd=$scheme://$http_host$request_uri"
    "nginx.ingress.kubernetes.io/auth-response-headers" = "Remote-User,Remote-Groups,Remote-Name,Remote-Email"
  }

  # Applied to every service ingress that admin.vinnel.cloud frames.
  #
  # admin.vinnel.cloud and the framed host share the registrable domain
  # vinnel.cloud, so the frame is same-SITE (cross-origin): the app's own
  # SameSite=Lax cookies still flow inside it and no browser partitions them.
  # The only thing blocking the frame is the app's own X-Frame-Options, and we
  # terminate TLS for all of these, so we clear it here.
  #
  # Deliberately NOT touching Content-Security-Policy wholesale: replacing it
  # with a bare frame-ancestors would also wipe each app's script-src/style-src
  # XSS protections. Header survey of 2026-07-29 put each host in one of three
  # buckets:
  #   - no CSP frame-ancestors (signoz, registry, nextcloud): this local is all
  #     they need. Note nextcloud sends X-Frame-Options but no frame-ancestors,
  #     and frame-ancestors does not fall back to default-src.
  #   - CSP is only frame-ancestors (ceph): replacing the whole header costs
  #     nothing, so platform-ceph.tf writes its snippet inline with an added
  #     more_set_headers. Re-check after a Rook upgrade.
  #   - CSP is large and upgrade-managed (netbird): pinning a rewritten copy here
  #     would go stale the next time Renovate bumps the image and silently
  #     override its script-src. Mark it Frameable=false in
  #     vinnel-cloud/admin/services.go and give its ingress plain
  #     authelia_forward_auth_annotations — WITHOUT the bounce below, which would
  #     otherwise catch the portal's own new-tab navigation to it.
  #
  # The Sec-Fetch-Dest bounce sends address-bar navigation to vinnel.cloud so the
  # portal is the way in. It is UX ONLY, not a security boundary: the header is
  # browser-supplied and any non-browser client simply omits it. Every host that
  # can take it also carries authelia_forward_auth_annotations above, and that is
  # the actual gate.
  admin_framed_annotations = {
    "nginx.ingress.kubernetes.io/configuration-snippet" = <<-EOT
      more_clear_headers "X-Frame-Options";
      if ($http_sec_fetch_dest = "document") {
        return 302 https://vinnel.cloud/;
      }
    EOT
  }

  # The common case: gated by Authelia and framed by the portal.
  admin_framed_service_annotations = merge(
    local.authelia_forward_auth_annotations,
    local.admin_framed_annotations,
  )
}
locals {
  images = jsondecode(file("${path.module}/images.json"))
}
