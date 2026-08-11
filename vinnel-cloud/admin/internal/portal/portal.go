package portal

import "html/template"

type Service struct {
	Slug      string
	Label     string
	Host      string
	Desc      string
	Group     string
	Frameable bool
	Icon      template.HTML
}

func (s Service) URL() string { return "https://" + s.Host + "/" }

const (
	iconChart    = `<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>`
	iconNetwork  = `<circle cx="12" cy="12" r="2"/><path d="M12 2v6M12 16v6M2 12h6M16 12h6"/><circle cx="12" cy="4" r="2"/><circle cx="12" cy="20" r="2"/><circle cx="4" cy="12" r="2"/><circle cx="20" cy="12" r="2"/>`
	iconShield   = `<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>`
	iconBox      = `<path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>`
	iconGlobe    = `<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 010 18a15 15 0 010-18z"/>`
	iconTerminal = `<polyline points="4 6 9 12 4 18"/><line x1="11" y1="18" x2="20" y2="18"/>`
	iconArchive  = `<rect x="3" y="3" width="18" height="5" rx="1"/><path d="M4 8v11a1 1 0 001 1h14a1 1 0 001-1V8"/><path d="M10 13h4"/>`
	iconDatabase = `<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0018 0V5"/><path d="M3 12a9 3 0 0018 0"/>`
	iconCloud    = `<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9z"/>`
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

var Services = []Service{
	{"signoz", "SigNoz", "signoz.vinnel.cloud", "Metrics, logs and traces", "Observability", true, iconChart},
	{"hubble", "Hubble", "hubble.vinnel.cloud", "Cilium network flows", "Observability", true, iconNetwork},
	{"adguard", "AdGuard", "adguard.vinnel.cloud", "DNS filtering", "Network", true, iconShield},
	{"proxy", "Netbird", "proxy.vinnel.cloud", "Mesh VPN", "Network", true, iconGlobe},
	{"seaweed", "SeaweedFS", "seaweed.vinnel.cloud", "Object storage", "Storage", true, iconDatabase},
	{"cloud", "Nextcloud", "cloud.vinnel.cloud", "Files & photos", "Storage", true, iconCloud},
	{"velero", "Velero", "velero.vinnel.cloud", "Backup & restore", "Storage", true, iconArchive},
	{"registry", "Harbor", "registry.vinnel.cloud", "Container registry", "Platform", true, iconBox},
	{"shell", "Shell", "shell.vinnel.cloud", "Cluster shell (kubectl)", "Platform", true, iconTerminal},
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
