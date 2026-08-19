resource "cloudflare_dns_record" "resend_dkim_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "resend._domainkey.vinnel.cloud"
  type    = "TXT"
  content = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCsFtlcD5SkCdzd7e6BQr6B2Yr/b2aq1jllcm1oxS12b4UmZFvaQ95yojWIUqlQ8x8jqQ6B57ZxT92DK3fxagZiCXrnVTC37MH/9/CS3J5IEG+j1h2gpfCDOA0LXcl3DvyrOxUiyrw0beuTOn8LB7QGl7+09OTkaUtNXZB/ef7PNwIDAQAB"
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "resend_mx_vinnel_cloud" {
  zone_id  = data.cloudflare_zone.vinnel_cloud.id
  name     = "mail.vinnel.cloud"
  type     = "MX"
  content  = "feedback-smtp.eu-west-1.amazonses.com"
  priority = 10
  ttl      = 1
  proxied  = false
}

resource "cloudflare_dns_record" "resend_spf_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "mail.vinnel.cloud"
  type    = "TXT"
  content = "v=spf1 include:amazonses.com ~all"
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "resend_tracking_vinnel_cloud" {
  zone_id = data.cloudflare_zone.vinnel_cloud.id
  name    = "links.vinnel.cloud"
  type    = "CNAME"
  content = "links1.resend-dns.com"
  ttl     = 1
  proxied = false
}
