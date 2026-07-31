locals {
  vin_moe_cluster_issuer       = "letsencrypt-prod-vin-moe"
  vinnel_cloud_cluster_issuer  = "letsencrypt-prod-vinnel-cloud"
  monke_academy_cluster_issuer = "letsencrypt-prod-monke-academy"

  authelia_forward_auth_annotations = {
    "nginx.ingress.kubernetes.io/auth-url"              = "http://authelia.services.svc.cluster.local/api/authz/auth-request"
    "nginx.ingress.kubernetes.io/auth-signin"           = "https://auth.vinnel.cloud/?rd=$scheme://$http_host$request_uri"
    "nginx.ingress.kubernetes.io/auth-response-headers" = "Remote-User,Remote-Groups,Remote-Name,Remote-Email"
  }

  admin_framed_annotations = {
    for slug in ["adguard", "signoz", "hubble", "shell", "nextcloud", "proxy"] : slug => {
      "nginx.ingress.kubernetes.io/configuration-snippet" = <<-EOT
        more_clear_headers "X-Frame-Options";
        if ($http_sec_fetch_dest = "document") {
          return 302 https://admin.vinnel.cloud/#${slug};
        }
      EOT
    }
  }

  admin_framed_service_annotations = {
    for slug, ann in local.admin_framed_annotations :
    slug => merge(local.authelia_forward_auth_annotations, ann)
  }
}
locals {
  images = jsondecode(file("${path.module}/images.json"))
}
