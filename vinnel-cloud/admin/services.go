package main

import "html/template"

// service is one entry in the portal. The portal frames https://<Host>/ directly:
// admin.vinnel.cloud and every Host below share the registrable domain
// vinnel.cloud, so the frame is same-SITE (cross-origin), which means each app's
// own SameSite=Lax session cookies still flow inside it and no browser cookie
// partitioning applies. The apps' X-Frame-Options headers are cleared at the
// ingress — see admin_framed_annotations in hestia/locals.tf.
//
// Frameable=false renders an open-in-new-tab link instead of loading the service
// into the frame. That is the escape hatch for an app that busts the frame from
// JS or whose framing headers we cannot rewrite cleanly.
type service struct {
	Slug      string
	Label     string
	Host      string
	Desc      string
	Frameable bool
	// Icon is inlined into the page unescaped. Every value is a compile-time
	// constant in this file; never populate it from a request or a config file.
	Icon template.HTML
}

func (s service) URL() string { return "https://" + s.Host + "/" }

const (
	iconChart   = `<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>`
	iconNetwork = `<circle cx="12" cy="12" r="2"/><path d="M12 2v6M12 16v6M2 12h6M16 12h6"/><circle cx="12" cy="4" r="2"/><circle cx="12" cy="20" r="2"/><circle cx="4" cy="12" r="2"/><circle cx="20" cy="12" r="2"/>`
	iconShield  = `<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>`
	iconDisk    = `<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>`
	iconFolder  = `<path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>`
	iconBox     = `<path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>`
	iconGlobe   = `<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 010 18a15 15 0 010-18z"/>`
)

// Adding a service here is the only edit the portal needs: it drives the sidebar,
// the tile grid and the frame-src CSP directive in main.go. The matching ingress
// still needs local.admin_framed_annotations applied in Terraform.
//
// dashboard.vinnel.cloud is deliberately absent — it is out of scope for the portal.
var services = []service{
	{"signoz", "SigNoz", "signoz.vinnel.cloud", "Metrics, logs and traces", true, iconChart},
	{"hubble", "Hubble", "hubble.vinnel.cloud", "Cilium network flows", true, iconNetwork},
	{"adguard", "AdGuard", "adguard.vinnel.cloud", "DNS filtering", true, iconShield},
	{"ceph", "Ceph", "ceph.vinnel.cloud", "Cluster storage", true, iconDisk},
	// Nextcloud sends X-Frame-Options: SAMEORIGIN but its CSP has NO
	// frame-ancestors directive (checked 2026-07-29), and frame-ancestors does not
	// fall back to default-src. Clearing the one header is enough, so its
	// nonce-based script-src survives untouched.
	{"nextcloud", "Nextcloud", "nextcloud.vinnel.cloud", "Files and sync", true, iconFolder},
	{"registry", "Harbor", "registry.vinnel.cloud", "Container registry", true, iconBox},
	// Not frameable: the netbird dashboard sends both X-Frame-Options: SAMEORIGIN
	// and a ~2KB CSP ending in frame-ancestors 'self'. Reproducing that CSP with
	// frame-ancestors swapped would mean pinning a copy of it here, and Renovate
	// bumps netbirdio/dashboard automatically — a stale copy would silently
	// override the image's own script-src after an upgrade. Opens in a new tab
	// instead, so its ingress takes plain forward-auth with no Sec-Fetch bounce.
	{"proxy", "Netbird", "proxy.vinnel.cloud", "Mesh VPN", false, iconGlobe},
}
