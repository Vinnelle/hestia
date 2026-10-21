package servers

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	relayID          = "relay"
	staleHandshake   = 180
	scrapeTimeout    = 5 * time.Second
	maxMetricsLength = 4 << 20
)

type sample struct {
	name   string
	labels map[string]string
	value  float64
}

type snapshot struct {
	at      time.Time
	samples []sample
}

type filter func(map[string]string) bool

type Relay struct {
	URL      string
	Location string
	Client   *http.Client

	mu     sync.Mutex
	prev   *snapshot
	latest Server
}

func (r *Relay) Run(ctx context.Context, every time.Duration) {
	r.poll(ctx)
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			r.poll(ctx)
		}
	}
}

func (r *Relay) Latest() Server {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.latest.ID == "" {
		s := r.base()
		s.Status = "waiting for the first scrape"
		return s
	}
	return r.latest
}

func (r *Relay) base() Server {
	return Server{ID: relayID, Name: relayID, Role: "WireGuard relay", Location: r.Location}
}

func (r *Relay) poll(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, scrapeTimeout)
	defer cancel()
	samples, err := r.scrape(ctx)
	now := time.Now()

	r.mu.Lock()
	defer r.mu.Unlock()
	if err != nil {
		r.prev = nil
		s := r.base()
		s.Status = "unreachable"
		s.Err = err.Error()
		r.latest = s
		return
	}
	cur := &snapshot{at: now, samples: samples}
	r.latest = r.build(r.prev, cur)
	r.prev = cur
}

func (r *Relay) scrape(ctx context.Context) ([]sample, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, r.URL, nil)
	if err != nil {
		return nil, err
	}
	client := r.Client
	if client == nil {
		client = &http.Client{Timeout: scrapeTimeout}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("relay metrics: %s", resp.Status)
	}
	return parse(io.LimitReader(resp.Body, maxMetricsLength))
}

func (r *Relay) build(prev, cur *snapshot) Server {
	s := r.base()
	s.Up = true
	s.Status = "up"
	m := window{prev: prev, cur: cur}

	cpu := Stat{Label: "CPU", Max: m.count("node_cpu_seconds_total", is("mode", "idle")), Unit: "cores", Unknown: true}
	if idle, ok := m.rate("node_cpu_seconds_total", is("mode", "idle")); ok {
		cpu.Value, cpu.Unknown = math.Max(cpu.Max-idle, 0), false
	}
	memTotal := m.sum("node_memory_MemTotal_bytes", nil)
	s.Stats = []Stat{
		cpu,
		{Label: "Memory", Value: memTotal - m.sum("node_memory_MemAvailable_bytes", nil), Max: memTotal, Unit: "bytes"},
		{Label: "Conntrack", Value: m.sum("node_nf_conntrack_entries", nil), Max: m.sum("node_nf_conntrack_entries_limit", nil), Unit: "count"},
		{Label: "Uptime", Value: m.sum("node_time_seconds", nil) - m.sum("node_boot_time_seconds", nil), Unit: "seconds"},
		m.rateStat("In", "bytes/s", "node_network_receive_bytes_total", publicInterface, 1),
		m.rateStat("Out", "bytes/s", "node_network_transmit_bytes_total", publicInterface, 1),
	}

	s.Apps = append(s.Apps, m.tunnel())
	s.Apps = append(s.Apps, m.forwards()...)
	s.Apps = append(s.Apps, m.firewall()...)
	return s
}

func (m window) tunnel() App {
	age := -1.0
	if handshake := m.sum("relay_wireguard_latest_handshake_seconds", nil); handshake > 0 {
		age = math.Max(m.sum("node_time_seconds", nil)-handshake, 0)
	}
	app := App{
		Group:  "Tunnel",
		Name:   "WireGuard",
		Detail: "to the home node",
		OK:     age >= 0 && age < staleHandshake,
		Stats: []Stat{
			{Label: "Last handshake", Value: age, Unit: "ago"},
			{Label: "Received", Value: m.sum("relay_wireguard_receive_bytes_total", nil), Unit: "bytes"},
			{Label: "Sent", Value: m.sum("relay_wireguard_transmit_bytes_total", nil), Unit: "bytes"},
			m.rateStat("In", "bytes/s", "relay_wireguard_receive_bytes_total", nil, 1),
			m.rateStat("Out", "bytes/s", "relay_wireguard_transmit_bytes_total", nil, 1),
		},
	}
	return app
}

func (m window) forwards() []App {
	var apps []App
	for _, smp := range m.cur.samples {
		if smp.name != "relay_forward_connections_total" {
			continue
		}
		name := smp.labels["forward"]
		same := is("forward", name)
		app := App{
			Group:  "Forwards",
			Name:   name,
			Detail: smp.labels["port"] + "/" + smp.labels["protocol"],
			OK:     true,
			Stats: []Stat{
				{Label: "Connections", Value: smp.value, Unit: "count"},
				{Label: "Traffic", Value: m.sum("relay_forward_bytes_total", same), Unit: "bytes"},
				m.rateStat("New", "per-minute", "relay_forward_connections_total", same, 60),
				m.rateStat("Throughput", "bytes/s", "relay_forward_bytes_total", same, 1),
			},
		}
		apps = append(apps, app)
	}
	sort.Slice(apps, func(i, j int) bool { return apps[i].Name < apps[j].Name })
	return apps
}

var chainDetail = map[string]string{
	"input":   "packets addressed to the relay",
	"forward": "packets the relay would not forward",
	"output":  "connections the relay tried to open itself",
}

func (m window) firewall() []App {
	var apps []App
	for _, chain := range []string{"input", "forward", "output"} {
		same := is("chain", chain)
		if m.count("relay_firewall_dropped_packets_total", same) == 0 {
			continue
		}
		dropped := m.sum("relay_firewall_dropped_packets_total", same)
		app := App{
			Group:  "Firewall",
			Name:   chain,
			Detail: chainDetail[chain],
			OK:     chain != "output" || dropped == 0,
			Stats: []Stat{
				{Label: "Dropped", Value: dropped, Unit: "count"},
				m.rateStat("Rate", "per-minute", "relay_firewall_dropped_packets_total", same, 60),
			},
		}
		apps = append(apps, app)
	}
	return apps
}

type window struct {
	prev, cur *snapshot
}

func is(key, value string) filter {
	return func(l map[string]string) bool { return l[key] == value }
}

func publicInterface(l map[string]string) bool {
	return l["device"] != "lo" && l["device"] != "wg0"
}

func total(s *snapshot, name string, keep filter) (float64, int) {
	var sum float64
	var n int
	for _, smp := range s.samples {
		if smp.name == name && (keep == nil || keep(smp.labels)) {
			sum += smp.value
			n++
		}
	}
	return sum, n
}

func (m window) sum(name string, keep filter) float64 {
	v, _ := total(m.cur, name, keep)
	return v
}

func (m window) count(name string, keep filter) float64 {
	_, n := total(m.cur, name, keep)
	return float64(n)
}

func (m window) rateStat(label, unit, name string, keep filter, scale float64) Stat {
	v, ok := m.rate(name, keep)
	return Stat{Label: label, Value: v * scale, Unit: unit, Unknown: !ok}
}

func (m window) rate(name string, keep filter) (float64, bool) {
	if m.prev == nil {
		return 0, false
	}
	elapsed := m.cur.at.Sub(m.prev.at).Seconds()
	before, nb := total(m.prev, name, keep)
	after, na := total(m.cur, name, keep)
	if elapsed <= 0 || nb == 0 || na == 0 || after < before {
		return 0, false
	}
	return (after - before) / elapsed, true
}

func parse(r io.Reader) ([]sample, error) {
	var samples []sample
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || line[0] == '#' {
			continue
		}
		smp, err := parseLine(line)
		if err != nil {
			return nil, err
		}
		samples = append(samples, smp)
	}
	return samples, sc.Err()
}

func parseLine(line string) (sample, error) {
	smp := sample{labels: map[string]string{}}
	i := strings.IndexAny(line, "{ \t")
	if i <= 0 {
		return smp, fmt.Errorf("malformed metric line %q", line)
	}
	smp.name = line[:i]
	rest := line[i:]
	if rest[0] == '{' {
		end, err := parseLabels(rest, smp.labels)
		if err != nil {
			return smp, fmt.Errorf("metric %s: %w", smp.name, err)
		}
		rest = rest[end:]
	}
	fields := strings.Fields(rest)
	if len(fields) == 0 {
		return smp, fmt.Errorf("metric %s has no value", smp.name)
	}
	v, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return smp, fmt.Errorf("metric %s: %w", smp.name, err)
	}
	smp.value = v
	return smp, nil
}

func parseLabels(s string, into map[string]string) (int, error) {
	i := 1
	for {
		for i < len(s) && (s[i] == ' ' || s[i] == ',') {
			i++
		}
		if i >= len(s) {
			return 0, errors.New("unterminated label set")
		}
		if s[i] == '}' {
			return i + 1, nil
		}
		eq := strings.IndexByte(s[i:], '=')
		if eq <= 0 {
			return 0, errors.New("label without a value")
		}
		key := strings.TrimSpace(s[i : i+eq])
		i += eq + 1
		if i >= len(s) || s[i] != '"' {
			return 0, errors.New("label value is not quoted")
		}
		i++
		var b strings.Builder
		for {
			if i >= len(s) {
				return 0, errors.New("unterminated label value")
			}
			c := s[i]
			if c == '\\' && i+1 < len(s) {
				switch s[i+1] {
				case 'n':
					b.WriteByte('\n')
				default:
					b.WriteByte(s[i+1])
				}
				i += 2
				continue
			}
			i++
			if c == '"' {
				break
			}
			b.WriteByte(c)
		}
		into[key] = b.String()
	}
}
