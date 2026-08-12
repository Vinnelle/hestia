package portal

import "html/template"

type Service struct {
	Slug      string
	Label     string
	Host      string
	Desc      string
	Group     string
	Frameable bool
	Icon      template.HTML // fallback inline icon, used only when IconURL is empty
	IconURL   string        // real logo, pulled from the service's own site
}

func (s Service) URL() string { return "https://" + s.Host + "/" }

const (
	iconChart    = `<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>`
	iconBox      = `<path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>`
	iconGlobe    = `<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 010 18a15 15 0 010-18z"/>`
	iconTerminal = `<polyline points="4 6 9 12 4 18"/><line x1="11" y1="18" x2="20" y2="18"/>`
	iconDatabase = `<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0018 0V5"/><path d="M3 12a9 3 0 0018 0"/>`
)

// groupIcons gives each sidebar category (both portal.Services groups and the
// hardcoded "Game Servers" section in index.html) its own icon, distinct from
// any one service's icon.
var groupIcons = map[string]template.HTML{
	"Observability": iconChart,
	"Network":       iconGlobe,
	"Storage":       iconDatabase,
	"Platform":      iconBox,
}

// IconURL is each service's own logo, pulled from its official site (curl-verified
// 2026-08-12). Shell has no real product/logo to pull — it keeps the generic
// terminal glyph via Icon instead.
var Services = []Service{
	{"signoz", "SigNoz", "signoz.vinnel.cloud", "Metrics, logs and traces", "Observability", true, "", "https://signoz.io/static/favicons/favicon-96x96.png"},
	{"hubble", "Hubble", "hubble.vinnel.cloud", "Cilium network flows", "Observability", true, "", "https://cdn.jsdelivr.net/gh/cilium/hubble@main/Documentation/images/hubble_logo.png"},
	{"adguard", "AdGuard", "adguard.vinnel.cloud", "DNS filtering", "Network", true, "", "https://st2.adguardcdn.com/favicons/adguard/favicon.svg"},
	{"proxy", "Netbird", "proxy.vinnel.cloud", "Mesh VPN", "Network", true, "", "https://netbird.io/icon.png"},
	{"seaweed", "SeaweedFS", "seaweed.vinnel.cloud", "Object storage", "Storage", true, "", "https://seaweedfs.com/images/seaweed-logo.png"},
	{"cloud", "Nextcloud", "cloud.vinnel.cloud", "Files & photos", "Storage", true, "", "https://nextcloud.com/c/uploads/2022/03/favicon.png"},
	{"velero", "Velero", "velero.vinnel.cloud", "Backup & restore", "Storage", true, "", "https://velero.io/favicon.ico"},
	{"registry", "Harbor", "registry.vinnel.cloud", "Container registry", "Platform", true, "", "https://goharbor.io/favicon.svg"},
	{"shell", "Shell", "shell.vinnel.cloud", "Cluster shell (kubectl)", "Platform", true, iconTerminal, ""},
}

type Group struct {
	Name     string
	Icon     template.HTML
	Services []Service
}

// Groups returns Services bucketed by their Group field, in first-seen order.
func Groups() []Group {
	var groups []Group
	index := map[string]int{}
	for _, s := range Services {
		i, ok := index[s.Group]
		if !ok {
			i = len(groups)
			index[s.Group] = i
			groups = append(groups, Group{Name: s.Group, Icon: groupIcons[s.Group]})
		}
		groups[i].Services = append(groups[i].Services, s)
	}
	return groups
}
