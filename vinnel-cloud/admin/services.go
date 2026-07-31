package main

import "html/template"

type service struct {
	Slug      string
	Label     string
	Host      string
	Desc      string
	Frameable bool
	Icon      template.HTML
}

func (s service) URL() string { return "https://" + s.Host + "/" }

const (
	iconChart    = `<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>`
	iconNetwork  = `<circle cx="12" cy="12" r="2"/><path d="M12 2v6M12 16v6M2 12h6M16 12h6"/><circle cx="12" cy="4" r="2"/><circle cx="12" cy="20" r="2"/><circle cx="4" cy="12" r="2"/><circle cx="20" cy="12" r="2"/>`
	iconShield   = `<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>`
	iconDisk     = `<ellipse cx="12" cy="6" rx="8" ry="3"/><path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>`
	iconFolder   = `<path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>`
	iconBox      = `<path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>`
	iconGlobe    = `<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 010 18a15 15 0 010-18z"/>`
	iconTerminal = `<polyline points="4 6 9 12 4 18"/><line x1="11" y1="18" x2="20" y2="18"/>`
)

var services = []service{
	{"signoz", "SigNoz", "signoz.vinnel.cloud", "Metrics, logs and traces", true, iconChart},
	{"hubble", "Hubble", "hubble.vinnel.cloud", "Cilium network flows", true, iconNetwork},
	{"adguard", "AdGuard", "adguard.vinnel.cloud", "DNS filtering", true, iconShield},
	{"ceph", "Ceph", "ceph.vinnel.cloud", "Cluster storage", true, iconDisk},
	{"nextcloud", "Nextcloud", "nextcloud.vinnel.cloud", "Files and sync", false, iconFolder},
	{"registry", "Harbor", "registry.vinnel.cloud", "Container registry", true, iconBox},
	{"proxy", "Netbird", "proxy.vinnel.cloud", "Mesh VPN", false, iconGlobe},
	{"shell", "Shell", "shell.vinnel.cloud", "Cluster shell (kubectl)", true, iconTerminal},
}
