package digest

import (
	"bytes"
	_ "embed"
	"fmt"
	"html/template"
	"math"
	"sort"
	"strings"
	"time"
)

//go:embed email.html
var emailHTML string

var colors = map[string]string{
	"ok":     "#2f7a45",
	"warn":   "#a76a12",
	"danger": "#b3261e",
	"accent": "#b3466b",
}

var pills = map[string]string{
	"ok":     "background:#e2efe5;color:#2f7a45;",
	"warn":   "background:#f6ead6;color:#a76a12;",
	"danger": "background:#f6dedc;color:#b3261e;",
}

func colorOf(tone string) string {
	if c, ok := colors[tone]; ok {
		return c
	}
	return "#625e57"
}

var page = template.Must(template.New("email").Funcs(template.FuncMap{
	"color": func(tone string) template.CSS { return template.CSS("color:" + colorOf(tone) + ";") },
	"bg":    func(tone string) template.CSS { return template.CSS("background:" + colorOf(tone) + ";") },
	"pill":  func(tone string) template.CSS { return template.CSS(pills[tone]) },
}).Parse(emailHTML))

type kpi struct {
	Label, Value, Sub, Tone string
}

type bar struct {
	Label, Value string
	Pct          int
	Tone         string
}

type line struct {
	Tone, Left, Text, Right, URL string
	Pct                          int
}

func plural(n int, word string) string {
	if n == 1 {
		return fmt.Sprintf("%d %s", n, word)
	}
	return fmt.Sprintf("%d %ss", n, word)
}

var statuses = map[string][2]string{
	Healthy:   {"All good", "ok"},
	Attention: {"Needs attention", "warn"},
	Action:    {"Action needed", "danger"},
}

type View struct {
	Date        string
	Window      string
	StatusLabel string
	StatusTone  string
	Headline    string
	Summary     string
	Attention   []line
	KPIs        []kpi
	Versions    string
	Disks       []bar
	PodIssues   []line
	Restarts    []line
	TopMemory   []line
	Hosts       []line
	TrafficNote string
	Upgrades    []line
	Commits     []line
	Merged      []line
	MergedNote  string
	Images      []line
	Workloads   []line
	Pipelines   []line
	Reviews     string
	NoChanges   bool
	Alerts      []line
	Vulns       string
	VulnNote    string
	Worst       []line
	Certs       []line
	AI          []line
	Suggestions []string
	Gaps        []string
	Footer      string
	AdminURL    string
	ModelErr    string
}

func humanBytes(b float64) string {
	units := []string{"B", "KiB", "MiB", "GiB", "TiB"}
	i := 0
	for b >= 1024 && i < len(units)-1 {
		b /= 1024
		i++
	}
	if i == 0 {
		return fmt.Sprintf("%.0f B", b)
	}
	if b >= 100 {
		return fmt.Sprintf("%.0f %s", b, units[i])
	}
	return fmt.Sprintf("%.1f %s", b, units[i])
}

func humanCount(n float64) string {
	switch {
	case n >= 1e6:
		return fmt.Sprintf("%.1fM", n/1e6)
	case n >= 1e4:
		return fmt.Sprintf("%.0fk", n/1e3)
	case n >= 1e3:
		return fmt.Sprintf("%.1fk", n/1e3)
	default:
		return fmt.Sprintf("%.0f", n)
	}
}

func delta(cur, prev float64) string {
	if prev <= 0 {
		return ""
	}
	d := (cur - prev) / prev * 100
	if math.Abs(d) < 0.5 {
		return "same as the day before"
	}
	sign := "+"
	if d < 0 {
		sign = "−"
	}
	return fmt.Sprintf("%s%.0f%% on the day before", sign, math.Abs(d))
}

func tone(severity string) string {
	switch severity {
	case "critical":
		return "danger"
	case "warning":
		return "warn"
	default:
		return "info"
	}
}

func usageTone(p float64) string {
	switch {
	case p >= 90:
		return "danger"
	case p >= 80:
		return "warn"
	default:
		return "ok"
	}
}

func clampPct(p float64) int {
	return int(math.Max(1, math.Min(100, math.Round(p))))
}

func Subject(s Summary, to time.Time) string {
	return fmt.Sprintf("hestia · %s · %s", to.Format("Mon 2 Jan"), statuses[s.Status][0])
}

func Build(f Facts, s Summary, checks []Concern, loc *time.Location, adminURL string) View {
	to, from := f.To.In(loc), f.From.In(loc)
	v := View{
		Date:     to.Format("Monday 2 January"),
		Headline: s.Headline,
		Summary:  s.Summary,
		AdminURL: adminURL,
		ModelErr: s.Err,
		Gaps:     f.Gaps,
	}
	switch {
	case f.First:
		v.Window = "The last 24 hours; this is the first digest"
	case to.Sub(from) < 36*time.Hour:
		v.Window = "Since " + from.Format("Monday 15:04")
	default:
		v.Window = "Since " + from.Format("Monday 2 January 15:04")
	}
	v.StatusLabel, v.StatusTone = statuses[s.Status][0], statuses[s.Status][1]

	all := append(append([]Concern{}, checks...), s.Concerns...)
	sort.SliceStable(all, func(i, j int) bool { return severityRank[all[i].Severity] > severityRank[all[j].Severity] })
	for _, c := range all {
		v.Attention = append(v.Attention, line{Tone: tone(c.Severity), Text: c.Text})
	}

	c := f.Cluster
	memPct := percent(c.Memory.Peak, c.Memory.Total)
	cpuPct := percent(c.CPU.Peak, c.CPU.Total)
	v.KPIs = []kpi{
		{Label: "Requests", Value: humanCount(f.Traffic.Requests), Sub: delta(f.Traffic.Requests, f.Traffic.PreviousRequests), Tone: "plain"},
		{Label: "CPU peak", Value: fmt.Sprintf("%.1f", c.CPU.Peak), Sub: fmt.Sprintf("of %.0f cores · now %.1f", c.CPU.Total, c.CPU.Used), Tone: usageTone(cpuPct)},
		{Label: "Memory peak", Value: fmt.Sprintf("%.0f%%", memPct), Sub: humanBytes(c.Memory.Peak) + " of " + humanBytes(c.Memory.Total), Tone: usageTone(memPct)},
		{Label: "Pods", Value: fmt.Sprintf("%d", c.PodsRunning), Sub: fmt.Sprintf("running of %d", c.PodsTotal), Tone: "ok"},
	}
	if c.PodsRunning < c.PodsTotal {
		v.KPIs[3].Tone = "warn"
	}
	var versions []string
	if c.Talos != "" {
		versions = append(versions, "Talos "+c.Talos)
	}
	if c.Kubernetes != "" {
		versions = append(versions, "Kubernetes "+c.Kubernetes)
	}
	if c.Kernel != "" {
		versions = append(versions, "kernel "+strings.TrimSuffix(c.Kernel, "-talos"))
	}
	v.Versions = strings.Join(versions, " · ")
	for _, fs := range c.Filesystems {
		p := percent(fs.Used, fs.Size)
		v.Disks = append(v.Disks, bar{Label: fs.Mount, Value: fmt.Sprintf("%s of %s", humanBytes(fs.Used), humanBytes(fs.Size)), Pct: clampPct(p), Tone: usageTone(p)})
	}
	for _, p := range c.PodIssues {
		v.PodIssues = append(v.PodIssues, line{Tone: "warn", Left: p.Reason, Text: p.Namespace + "/" + p.Pod})
	}
	for _, r := range c.Restarts {
		v.Restarts = append(v.Restarts, line{Text: r.Namespace + "/" + r.Pod, Right: fmt.Sprintf("%d×", r.Count)})
	}
	for _, n := range c.TopMemory {
		v.TopMemory = append(v.TopMemory, line{Text: n.Namespace, Right: fmt.Sprintf("%s · %.2f cores", humanBytes(n.Memory), n.CPU)})
	}

	t := f.Traffic
	top := 0.0
	for _, h := range t.Hosts {
		top = math.Max(top, h.Requests)
	}
	for _, h := range t.Hosts {
		errs := ""
		errTone := ""
		if h.Errors >= 1 {
			errs = humanCount(h.Errors) + " 5xx"
			errTone = "warn"
		}
		v.Hosts = append(v.Hosts, line{Tone: errTone, Text: h.Host, Left: errs, Right: humanCount(h.Requests) + " · " + humanBytes(h.Bytes), Pct: clampPct(percent(h.Requests, top))})
	}
	var notes []string
	if t.Requests > 0 {
		notes = append(notes, fmt.Sprintf("%s out", humanBytes(t.BytesOut)))
		if t.ServerErrors > 0 || t.ClientErrors > 0 {
			notes = append(notes, fmt.Sprintf("%s server and %s client errors", humanCount(t.ServerErrors), humanCount(t.ClientErrors)))
		}
	}
	if t.TunnelIn > 0 || t.TunnelOut > 0 {
		notes = append(notes, fmt.Sprintf("%s in and %s out through the relay", humanBytes(t.TunnelIn), humanBytes(t.TunnelOut)))
	}
	v.TrafficNote = strings.Join(notes, " · ")

	ch := f.Changes
	for _, u := range ch.Upgrades {
		v.Upgrades = append(v.Upgrades, line{Tone: "accent", Text: u})
	}
	for _, cm := range ch.Commits {
		v.Commits = append(v.Commits, line{Left: cm.SHA, Text: cm.Title, Right: cm.Author, URL: cm.URL})
	}
	renovate := 0
	for _, m := range ch.Merged {
		if m.Renovate {
			renovate++
			continue
		}
		v.Merged = append(v.Merged, line{Left: fmt.Sprintf("!%d", m.IID), Text: m.Title, URL: m.URL})
	}
	var merged []string
	if renovate > 0 {
		merged = append(merged, plural(renovate, "Renovate update")+" merged")
	}
	if ch.ImagePins > 0 {
		merged = append(merged, plural(ch.ImagePins, "image pin")+" by CI")
	}
	if ch.OpenRenovate > 0 {
		merged = append(merged, plural(ch.OpenRenovate, "Renovate merge request")+" open")
	}
	v.MergedNote = strings.Join(merged, " · ")
	for _, im := range ch.Images {
		v.Images = append(v.Images, line{Text: im.Workload, Left: im.From, Right: im.To})
	}
	for _, w := range ch.Added {
		v.Workloads = append(v.Workloads, line{Tone: "ok", Left: "new", Text: w})
	}
	for _, w := range ch.Removed {
		v.Workloads = append(v.Workloads, line{Tone: "warn", Left: "gone", Text: w})
	}
	for _, p := range ch.FailedPipelines {
		v.Pipelines = append(v.Pipelines, line{Tone: "warn", Left: fmt.Sprintf("#%d", p.ID), Text: p.Ref, URL: p.URL})
	}
	var reviews []string
	for _, verdict := range []string{"safe", "check", "breaking"} {
		if n := ch.Reviews[verdict]; n > 0 {
			reviews = append(reviews, fmt.Sprintf("%d %s", n, verdict))
		}
	}
	if len(reviews) > 0 {
		v.Reviews = "Renovate reviews: " + strings.Join(reviews, ", ")
	}
	v.NoChanges = len(v.Upgrades)+len(v.Commits)+len(v.Merged)+len(v.Images)+len(v.Workloads)+len(v.Pipelines) == 0 && v.MergedNote == "" && v.Reviews == ""

	for _, a := range f.Alerts {
		state, tn := "resolved", "info"
		switch {
		case a.Firing && a.Severity == "critical":
			state, tn = "firing", "danger"
		case a.Firing:
			state, tn = "firing", "warn"
		}
		v.Alerts = append(v.Alerts, line{Tone: tn, Left: state, Text: a.Name, Right: strings.Trim(a.Severity+" · "+a.Namespace, " ·")})
	}

	sec := f.Security
	v.Vulns = fmt.Sprintf("%d critical · %d high", sec.Critical, sec.High)
	if sec.Known {
		if sec.Critical != sec.PrevCritical || sec.High != sec.PrevHigh {
			v.VulnNote = fmt.Sprintf("was %d critical · %d high", sec.PrevCritical, sec.PrevHigh)
		} else {
			v.VulnNote = "unchanged"
		}
	}
	for _, w := range sec.Worst {
		v.Worst = append(v.Worst, line{Text: w.Image, Right: fmt.Sprintf("%d critical", w.Critical)})
	}
	for _, cert := range f.Certificates {
		tn := "ok"
		switch {
		case !cert.Ready || cert.Days < 7:
			tn = "danger"
		case cert.Days < certWarnDays:
			tn = "warn"
		}
		right := fmt.Sprintf("%.0f days", cert.Days)
		if !cert.Ready {
			right = "not ready"
		}
		v.Certs = append(v.Certs, line{Tone: tn, Text: cert.Namespace + "/" + cert.Name, Right: right})
	}

	a := f.AI
	if a.PromptTokens > 0 || a.GeneratedTokens > 0 {
		v.AI = append(v.AI, line{Text: "Tokens read · written", Right: humanCount(a.PromptTokens) + " · " + humanCount(a.GeneratedTokens)})
	}
	if a.Speed > 0 {
		v.AI = append(v.AI, line{Text: "Generation speed", Right: fmt.Sprintf("%.0f tokens/s", a.Speed)})
	}
	if a.VRAMTotal > 0 {
		v.AI = append(v.AI, line{Text: "VRAM in use", Right: humanBytes(a.VRAMUsed) + " of " + humanBytes(a.VRAMTotal)})
	}
	if a.GPUTempMax > 0 {
		v.AI = append(v.AI, line{Text: "GPU peak temperature · average power", Right: fmt.Sprintf("%.0f °C · %.0f W", a.GPUTempMax, a.GPUPowerAvg)})
	}
	v.Suggestions = s.Suggestions

	model := s.Model
	if model == "" {
		model = "no model"
	}
	gpu := ""
	if a.GPU != "" {
		gpu = " on " + a.GPU
	}
	v.Footer = fmt.Sprintf("Collected on hestia, summarised by %s%s. Window %s → %s.", model, gpu, from.Format("Mon 15:04"), to.Format("Mon 15:04 MST"))
	return v
}

func Render(v View) (string, error) {
	var b bytes.Buffer
	if err := page.Execute(&b, v); err != nil {
		return "", err
	}
	return b.String(), nil
}

func Text(v View) string {
	var b strings.Builder
	fmt.Fprintf(&b, "hestia — %s\n%s\n\n%s: %s\n", v.Date, v.Window, v.StatusLabel, v.Headline)
	if v.Summary != "" {
		fmt.Fprintf(&b, "%s\n", v.Summary)
	}
	section := func(title string, lines []line) {
		if len(lines) == 0 {
			return
		}
		fmt.Fprintf(&b, "\n%s\n", strings.ToUpper(title))
		for _, l := range lines {
			fmt.Fprintf(&b, "  %s\n", strings.Join(strings.Fields(strings.Join([]string{l.Left, l.Text, l.Right}, "  ")), " "))
		}
	}
	section("Needs attention", v.Attention)
	fmt.Fprintf(&b, "\nNUMBERS\n")
	for _, k := range v.KPIs {
		fmt.Fprintf(&b, "  %-12s %s  %s\n", k.Label, k.Value, k.Sub)
	}
	section("Traffic", v.Hosts)
	section("Upgrades", v.Upgrades)
	section("Commits", v.Commits)
	section("Merged", v.Merged)
	if v.MergedNote != "" {
		fmt.Fprintf(&b, "  %s\n", v.MergedNote)
	}
	section("Images", v.Images)
	section("Workloads", v.Workloads)
	section("Failed pipelines", v.Pipelines)
	section("Alerts", v.Alerts)
	section("Certificates", v.Certs)
	section("LLM and GPU", v.AI)
	if len(v.Suggestions) > 0 {
		fmt.Fprintf(&b, "\nSUGGESTIONS\n")
		for _, s := range v.Suggestions {
			fmt.Fprintf(&b, "  - %s\n", s)
		}
	}
	fmt.Fprintf(&b, "\n%s\n%s\n", v.Footer, v.AdminURL)
	return b.String()
}
