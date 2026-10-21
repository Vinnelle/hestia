package servers

import (
	"sync"
	"time"

	"vinnel-cloud-admin/internal/cluster"
	"vinnel-cloud-admin/internal/kube"
)

type Stat struct {
	Label   string  `json:"label"`
	Value   float64 `json:"value"`
	Max     float64 `json:"max,omitempty"`
	Unit    string  `json:"unit"`
	Unknown bool    `json:"unknown,omitempty"`
}

type App struct {
	Group  string `json:"group"`
	Name   string `json:"name"`
	Detail string `json:"detail,omitempty"`
	OK     bool   `json:"ok"`
	Stats  []Stat `json:"stats"`
}

type Server struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Role     string `json:"role"`
	Location string `json:"location"`
	Up       bool   `json:"up"`
	Status   string `json:"status"`
	Err      string `json:"err,omitempty"`
	Stats    []Stat `json:"stats"`
	Apps     []App  `json:"apps"`
}

type Info struct {
	ID   string
	Name string
}

type Collector struct {
	Kube         *kube.Client
	ClusterStats func() cluster.Stats
	NodeLocation string
	Relay        *Relay
	TTL          time.Duration

	mu   sync.Mutex
	at   time.Time
	node Server
}

func (c *Collector) Infos() []Info {
	infos := []Info{{ID: nodeID, Name: nodeID}}
	if c.Relay != nil {
		infos = append(infos, Info{ID: relayID, Name: relayID})
	}
	return infos
}

func (c *Collector) Servers() []Server {
	servers := []Server{c.nodeServer()}
	if c.Relay != nil {
		servers = append(servers, c.Relay.Latest())
	}
	return servers
}

func (c *Collector) nodeServer() Server {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.node.ID != "" && time.Since(c.at) < c.TTL {
		return c.node
	}
	c.node = c.collectNode()
	c.at = time.Now()
	return c.node
}
