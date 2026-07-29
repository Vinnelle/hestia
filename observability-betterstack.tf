
resource "cloudflare_dns_record" "status_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "status.vinnel.cloud"
  type    = "CNAME"
  content = "vinnel.betteruptime.com"
  ttl     = 1
  proxied = true
}