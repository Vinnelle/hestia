package servers

import (
	"encoding/json"
	"math"
	"strings"
	"testing"
	"time"
)

const firstScrape = `# HELP node_cpu_seconds_total Seconds the CPUs spent in each mode.
# TYPE node_cpu_seconds_total counter
node_cpu_seconds_total{cpu="0",mode="idle"} 100
node_cpu_seconds_total{cpu="0",mode="system"} 5
node_memory_MemTotal_bytes 1.073741824e+09
node_memory_MemAvailable_bytes 8.05306368e+08
node_network_receive_bytes_total{device="eth0"} 1000
node_network_receive_bytes_total{device="lo"} 999999
node_network_receive_bytes_total{device="wg0"} 500
node_network_transmit_bytes_total{device="eth0"} 2000
node_nf_conntrack_entries 12
node_nf_conntrack_entries_limit 65536
node_boot_time_seconds 1.7e+09
node_time_seconds 1.7000036e+09
relay_wireguard_latest_handshake_seconds 1.70000359e+09
relay_wireguard_receive_bytes_total 4096
relay_wireguard_transmit_bytes_total 8192
relay_forward_connections_total{forward="https",port="443",protocol="tcp"} 10
relay_forward_bytes_total{forward="https",port="443",protocol="tcp"} 30000
relay_forward_connections_total{forward="minecraft",port="25565",protocol="tcp"} 0
relay_forward_bytes_total{forward="minecraft",port="25565",protocol="tcp"} 0
relay_firewall_dropped_packets_total{chain="input"} 40
relay_firewall_dropped_packets_total{chain="forward"} 0
relay_firewall_dropped_packets_total{chain="output"} 0
`

const secondScrape = `node_cpu_seconds_total{cpu="0",mode="idle"} 110.5
node_cpu_seconds_total{cpu="0",mode="system"} 9.5
node_memory_MemTotal_bytes 1.073741824e+09
node_memory_MemAvailable_bytes 8.05306368e+08
node_network_receive_bytes_total{device="eth0"} 16000
node_network_receive_bytes_total{device="lo"} 1999999
node_network_receive_bytes_total{device="wg0"} 900
node_network_transmit_bytes_total{device="eth0"} 32000
node_nf_conntrack_entries 15
node_nf_conntrack_entries_limit 65536
node_boot_time_seconds 1.7e+09
node_time_seconds 1.700003615e+09
relay_wireguard_latest_handshake_seconds 1.70000359e+09
relay_wireguard_receive_bytes_total 7096
relay_wireguard_transmit_bytes_total 14192
relay_forward_connections_total{forward="https",port="443",protocol="tcp"} 25
relay_forward_bytes_total{forward="https",port="443",protocol="tcp"} 60000
relay_forward_connections_total{forward="minecraft",port="25565",protocol="tcp"} 0
relay_forward_bytes_total{forward="minecraft",port="25565",protocol="tcp"} 0
relay_firewall_dropped_packets_total{chain="input"} 70
relay_firewall_dropped_packets_total{chain="forward"} 0
relay_firewall_dropped_packets_total{chain="output"} 3
`

func mustParse(t *testing.T, text string) []sample {
	t.Helper()
	samples, err := parse(strings.NewReader(text))
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	return samples
}

func stat(t *testing.T, stats []Stat, label string) Stat {
	t.Helper()
	for _, s := range stats {
		if s.Label == label {
			return s
		}
	}
	t.Fatalf("no %q stat in %+v", label, stats)
	return Stat{}
}

func near(a, b float64) bool { return math.Abs(a-b) < 1e-6 }

func TestParseHandlesLabelsEscapesAndSpecialValues(t *testing.T) {
	samples := mustParse(t, "# comment\n"+
		`plain 1.5e+03`+"\n"+
		`labelled{a="x",b="with \"quotes\", commas and \\ slashes"} 7 1700000000000`+"\n"+
		`weird{a="multi\nline"} +Inf`+"\n"+
		`nan NaN`+"\n")
	if len(samples) != 4 {
		t.Fatalf("got %d samples, want 4", len(samples))
	}
	if samples[0].name != "plain" || samples[0].value != 1500 {
		t.Errorf("plain = %+v", samples[0])
	}
	if got := samples[1].labels["b"]; got != `with "quotes", commas and \ slashes` {
		t.Errorf("escaped label = %q", got)
	}
	if samples[1].value != 7 {
		t.Errorf("value ignoring timestamp = %v", samples[1].value)
	}
	if samples[2].labels["a"] != "multi\nline" || !math.IsInf(samples[2].value, 1) {
		t.Errorf("weird = %+v", samples[2])
	}
	if !math.IsNaN(samples[3].value) {
		t.Errorf("nan = %v", samples[3].value)
	}
}

func TestParseRejectsGarbage(t *testing.T) {
	for _, bad := range []string{`{a="b"} 1`, `name{a="b" 1`, `name{a=b} 1`, `name`, `name{a="b"}`, `name x`} {
		if _, err := parse(strings.NewReader(bad + "\n")); err == nil {
			t.Errorf("parse(%q) succeeded", bad)
		}
	}
}

func TestRelayFirstScrapeKeepsLayoutWithUnknownRates(t *testing.T) {
	r := &Relay{Location: "Infomaniak"}
	s := r.build(nil, &snapshot{at: time.Unix(0, 0), samples: mustParse(t, firstScrape)})
	if !s.Up || s.Status != "up" || s.Location != "Infomaniak" {
		t.Fatalf("server = %+v", s)
	}
	var labels []string
	for _, st := range s.Stats {
		labels = append(labels, st.Label)
		if rate := st.Label == "CPU" || st.Label == "In" || st.Label == "Out"; st.Unknown != rate {
			t.Errorf("%s unknown = %v on the first scrape", st.Label, st.Unknown)
		}
	}
	if got, want := strings.Join(labels, ","), "CPU,Memory,Conntrack,Uptime,In,Out"; got != want {
		t.Errorf("stats = %s, want %s", got, want)
	}
	columns := map[string]int{"Tunnel": 5, "Forwards": 4, "Firewall": 2}
	for _, app := range s.Apps {
		if len(app.Stats) != columns[app.Group] {
			t.Errorf("%s %s has %d stats, want %d", app.Group, app.Name, len(app.Stats), columns[app.Group])
		}
		for _, st := range app.Stats {
			if rate := st.Unit == "bytes/s" || st.Unit == "per-minute"; st.Unknown != rate {
				t.Errorf("%s %s unknown = %v on the first scrape", app.Name, st.Label, st.Unknown)
			}
		}
	}
	if up := stat(t, s.Stats, "Uptime"); !near(up.Value, 3600) {
		t.Errorf("uptime = %v, want 3600", up.Value)
	}
}

func TestRelayRatesAndApps(t *testing.T) {
	r := &Relay{Location: "Infomaniak"}
	start := time.Unix(1700000000, 0)
	prev := &snapshot{at: start, samples: mustParse(t, firstScrape)}
	cur := &snapshot{at: start.Add(15 * time.Second), samples: mustParse(t, secondScrape)}
	s := r.build(prev, cur)

	if cpu := stat(t, s.Stats, "CPU"); !near(cpu.Value, 0.3) || cpu.Max != 1 {
		t.Errorf("cpu = %+v, want 0.3 of 1 core", cpu)
	}
	if mem := stat(t, s.Stats, "Memory"); !near(mem.Value, 268435456) || !near(mem.Max, 1073741824) {
		t.Errorf("memory = %+v", mem)
	}
	if in := stat(t, s.Stats, "In"); !near(in.Value, 1000) {
		t.Errorf("in = %v, want 1000 B/s (lo and wg0 excluded)", in.Value)
	}
	if out := stat(t, s.Stats, "Out"); !near(out.Value, 2000) {
		t.Errorf("out = %v, want 2000 B/s", out.Value)
	}
	if ct := stat(t, s.Stats, "Conntrack"); ct.Value != 15 || ct.Max != 65536 {
		t.Errorf("conntrack = %+v", ct)
	}

	groups := map[string][]App{}
	for _, a := range s.Apps {
		groups[a.Group] = append(groups[a.Group], a)
	}
	tunnel := groups["Tunnel"]
	if len(tunnel) != 1 || !tunnel[0].OK {
		t.Fatalf("tunnel = %+v", tunnel)
	}
	if hs := stat(t, tunnel[0].Stats, "Last handshake"); !near(hs.Value, 25) {
		t.Errorf("handshake age = %v, want 25s", hs.Value)
	}
	if in := stat(t, tunnel[0].Stats, "In"); !near(in.Value, 200) {
		t.Errorf("tunnel in = %v, want 200 B/s", in.Value)
	}

	forwards := groups["Forwards"]
	if len(forwards) != 2 || forwards[0].Name != "https" || forwards[1].Name != "minecraft" {
		t.Fatalf("forwards = %+v", forwards)
	}
	if forwards[0].Detail != "443/tcp" {
		t.Errorf("https detail = %q", forwards[0].Detail)
	}
	if n := stat(t, forwards[0].Stats, "New"); !near(n.Value, 60) {
		t.Errorf("https new connections = %v, want 60/min", n.Value)
	}
	if tp := stat(t, forwards[0].Stats, "Throughput"); !near(tp.Value, 2000) {
		t.Errorf("https throughput = %v, want 2000 B/s", tp.Value)
	}

	firewall := groups["Firewall"]
	if len(firewall) != 3 {
		t.Fatalf("firewall = %+v", firewall)
	}
	for _, a := range firewall {
		want := a.Name != "output"
		if a.OK != want {
			t.Errorf("firewall %s ok = %v, want %v", a.Name, a.OK, want)
		}
	}
	if rate := stat(t, firewall[0].Stats, "Rate"); !near(rate.Value, 120) {
		t.Errorf("input drop rate = %v, want 120/min", rate.Value)
	}
}

func TestRelayCounterResetMarksRatesUnknown(t *testing.T) {
	r := &Relay{}
	start := time.Unix(0, 0)
	prev := &snapshot{at: start, samples: mustParse(t, secondScrape)}
	cur := &snapshot{at: start.Add(15 * time.Second), samples: mustParse(t, firstScrape)}
	s := r.build(prev, cur)
	for _, label := range []string{"CPU", "In"} {
		if st := stat(t, s.Stats, label); !st.Unknown || st.Value != 0 {
			t.Errorf("counter reset still produced %s = %v", label, st.Value)
		}
	}
}

func TestRelayLatestBeforeFirstScrape(t *testing.T) {
	s := (&Relay{Location: "Infomaniak"}).Latest()
	if s.ID != relayID || s.Up || s.Status == "" {
		t.Errorf("latest before scrape = %+v", s)
	}
}

func TestNamespaceApps(t *testing.T) {
	var pods podList
	var usage podMetricsList
	mustJSON(t, `{"items": [
		{"metadata": {"namespace": "forge"}, "status": {"phase": "Running", "containerStatuses": [{"restartCount": 2}]}},
		{"metadata": {"namespace": "forge"}, "status": {"phase": "Running", "containerStatuses": [{"restartCount": 0}]}},
		{"metadata": {"namespace": "backup"}, "status": {"phase": "Succeeded"}},
		{"metadata": {"namespace": "games"}, "status": {"phase": "Running", "containerStatuses": [{"restartCount": 5, "state": {"waiting": {"reason": "CrashLoopBackOff"}}}]}},
		{"metadata": {"namespace": "files"}, "status": {"phase": "Pending"}}
	]}`, &pods)
	mustJSON(t, `{"items": [
		{"metadata": {"namespace": "forge"}, "containers": [{"usage": {"cpu": "250m", "memory": "1Gi"}}, {"usage": {"cpu": "50m", "memory": "512Mi"}}]},
		{"metadata": {"namespace": "games"}, "containers": [{"usage": {"cpu": "1", "memory": "4Gi"}}]}
	]}`, &usage)

	apps := namespaceApps(pods, usage)
	names := []string{}
	for _, a := range apps {
		names = append(names, a.Name)
	}
	if got := strings.Join(names, ","); got != "games,forge,backup,files" {
		t.Fatalf("order = %s, want games,forge,backup,files (by memory, then name)", got)
	}
	byName := map[string]App{}
	for _, a := range apps {
		byName[a.Name] = a
	}
	forge := byName["forge"]
	if !forge.OK || forge.Group != namespacesGroup {
		t.Errorf("forge = %+v", forge)
	}
	if p := stat(t, forge.Stats, "Pods"); p.Value != 2 || p.Max != 2 {
		t.Errorf("forge pods = %+v", p)
	}
	if c := stat(t, forge.Stats, "CPU"); !near(c.Value, 0.3) {
		t.Errorf("forge cpu = %v", c.Value)
	}
	if m := stat(t, forge.Stats, "Memory"); !near(m.Value, 1.5*(1<<30)) {
		t.Errorf("forge memory = %v", m.Value)
	}
	if r := stat(t, forge.Stats, "Restarts"); r.Value != 2 {
		t.Errorf("forge restarts = %v", r.Value)
	}
	if byName["games"].OK || byName["files"].OK {
		t.Errorf("crashlooping or pending namespaces reported ok")
	}
	if p := stat(t, byName["backup"].Stats, "Pods"); !byName["backup"].OK || p.Max != 0 {
		t.Errorf("completed jobs should not count as live pods: %+v", byName["backup"])
	}
}

func TestCollectorWithoutKube(t *testing.T) {
	c := &Collector{NodeLocation: "home", Relay: &Relay{}, TTL: time.Minute}
	servers := c.Servers()
	if len(servers) != 2 || servers[0].ID != nodeID || servers[0].Up || servers[0].Err == "" || servers[1].ID != relayID {
		t.Errorf("servers = %+v", servers)
	}
	if infos := c.Infos(); len(infos) != 2 || infos[1].ID != relayID {
		t.Errorf("infos = %+v", infos)
	}
	if infos := (&Collector{}).Infos(); len(infos) != 1 {
		t.Errorf("collector without a relay lists %+v", infos)
	}
}

func mustJSON(t *testing.T, text string, into any) {
	t.Helper()
	if err := json.Unmarshal([]byte(text), into); err != nil {
		t.Fatal(err)
	}
}
