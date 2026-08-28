package portal

import "html/template"

type Service struct {
	Slug      string
	Label     string
	Host      string
	Group     string
	Frameable bool
	Icon      template.HTML
	IconURL   string
}

func (s Service) URL() string { return "https://" + s.Host + "/" }

const (
	iconChart    = `<path d="M18 20V10"/><path d="M12 20V4"/><path d="M6 20v-6"/>`
	iconBox      = `<path d="M21 8l-9-5-9 5 9 5 9-5z"/><path d="M3 8v8l9 5 9-5V8"/><path d="M12 13v8"/>`
	iconGlobe    = `<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a15 15 0 010 18a15 15 0 010-18z"/>`
	iconTerminal = `<polyline points="4 6 9 12 4 18"/><line x1="11" y1="18" x2="20" y2="18"/>`
	iconDatabase = `<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14a9 3 0 0018 0V5"/><path d="M3 12a9 3 0 0018 0"/>`
	iconActivity = `<path d="M3 12h4l3 8 4-16 3 8h4"/>`
	iconFlows    = `<path d="M4 8h10"/><path d="M11 5l3 3-3 3"/><path d="M20 16H10"/><path d="M13 13l-3 3 3 3"/>`
	iconShield   = `<path d="M12 3L5 6v5.5c0 4.5 3.1 7 7 8.5 3.9-1.5 7-4 7-8.5V6z"/>`
	iconMesh     = `<circle cx="12" cy="5" r="2"/><circle cx="5" cy="17" r="2"/><circle cx="19" cy="17" r="2"/><path d="M10.4 6.4L6.6 15.2"/><path d="M13.6 6.4l3.8 8.8"/><path d="M7 17h10"/>`
	iconLayers   = `<path d="M12 3L3 7.5l9 4.5 9-4.5z"/><path d="M3 12l9 4.5 9-4.5"/><path d="M3 16.5L12 21l9-4.5"/>`
	iconCloud    = `<path d="M7 19a4 4 0 01-.4-8A5.5 5.5 0 0117.5 10a4 4 0 01.5 9z"/>`
	iconArchive  = `<path d="M3 4h18v4H3z"/><path d="M5 8v12h14V8"/><path d="M10 12h4"/>`
)

var groupIcons = map[string]template.HTML{
	"Observability": iconChart,
	"Network":       iconGlobe,
	"Storage":       iconDatabase,
	"Platform":      iconBox,
}

var Services = []Service{
	{"signoz", "SigNoz", "signoz.vinnel.cloud", "Observability", true, iconActivity, ""},
	{"glitchtip", "GlitchTip", "glitchtip.vinnel.cloud", "Observability", true, iconActivity, ""},
	{"hubble", "Hubble", "hubble.vinnel.cloud", "Observability", true, iconFlows, ""},
	{"adguard", "AdGuard", "adguard.vinnel.cloud", "Network", true, iconShield, ""},
	{"proxy", "Netbird", "netbird.vinnel.cloud", "Network", true, iconMesh, ""},
	{"seaweed", "SeaweedFS", "seaweed.vinnel.cloud", "Storage", true, iconLayers, ""},
	{"cloud", "Nextcloud", "cloud.vinnel.cloud", "Storage", true, iconCloud, ""},
	{"velero", "Velero", "velero.vinnel.cloud", "Storage", true, iconArchive, ""},
	{"shell", "Shell", "shell.vinnel.cloud", "Platform", true, iconTerminal, ""},
}

type Group struct {
	Name     string
	Icon     template.HTML
	Services []Service
}

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
