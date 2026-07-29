package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// Talks to the Kubernetes API with the pod's own ServiceAccount. Deliberately
// not client-go: three GETs against two well-known endpoints do not justify the
// dependency, and metrics.k8s.io is already served by the metrics-server that
// platform-vpa.tf installs for the VPA.
const (
	saDir      = "/var/run/secrets/kubernetes.io/serviceaccount"
	nodesPath  = "/api/v1/nodes"
	podsPath   = "/api/v1/pods"
	nodeMetric = "/apis/metrics.k8s.io/v1beta1/nodes"
)

type nodeStat struct {
	Name       string  `json:"name"`
	Ready      bool    `json:"ready"`
	CPUUsed    float64 `json:"cpuUsed"`  // cores
	CPUTotal   float64 `json:"cpuTotal"` // cores
	MemUsed    float64 `json:"memUsed"`  // bytes
	MemTotal   float64 `json:"memTotal"` // bytes
	PodCount   int     `json:"podCount"`
	PodTotal   int     `json:"podTotal"`
	Kubelet    string  `json:"kubelet"`
	CPUPercent float64 `json:"cpuPercent"`
	MemPercent float64 `json:"memPercent"`
}

type clusterStats struct {
	Nodes       []nodeStat `json:"nodes"`
	NodesReady  int        `json:"nodesReady"`
	PodsRunning int        `json:"podsRunning"`
	PodsTotal   int        `json:"podsTotal"`
	CPUUsed     float64    `json:"cpuUsed"`
	CPUTotal    float64    `json:"cpuTotal"`
	MemUsed     float64    `json:"memUsed"`
	MemTotal    float64    `json:"memTotal"`
	Err         string     `json:"err,omitempty"`
}

type kubeClient struct {
	host  string
	token string
	http  *http.Client
}

func newKubeClient() (*kubeClient, error) {
	host := os.Getenv("KUBERNETES_SERVICE_HOST")
	port := env("KUBERNETES_SERVICE_PORT", "443")
	if host == "" {
		return nil, fmt.Errorf("not running in-cluster: KUBERNETES_SERVICE_HOST unset")
	}
	token, err := os.ReadFile(saDir + "/token")
	if err != nil {
		return nil, fmt.Errorf("read service account token: %w", err)
	}
	ca, err := os.ReadFile(saDir + "/ca.crt")
	if err != nil {
		return nil, fmt.Errorf("read service account CA: %w", err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		return nil, fmt.Errorf("service account CA is not valid PEM")
	}
	return &kubeClient{
		host:  "https://" + host + ":" + port,
		token: strings.TrimSpace(string(token)),
		http: &http.Client{
			Timeout:   10 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}},
		},
	}, nil
}

func (k *kubeClient) get(path string, out any) error {
	req, err := http.NewRequest("GET", k.host+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+k.token)
	req.Header.Set("Accept", "application/json")
	resp, err := k.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s: %s", path, resp.Status)
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// Kubernetes quantities: CPU as "1500m" or "2", memory as "16008812Ki".
func parseCPU(s string) float64 {
	if strings.HasSuffix(s, "n") {
		v, _ := strconv.ParseFloat(strings.TrimSuffix(s, "n"), 64)
		return v / 1e9
	}
	if strings.HasSuffix(s, "u") {
		v, _ := strconv.ParseFloat(strings.TrimSuffix(s, "u"), 64)
		return v / 1e6
	}
	if strings.HasSuffix(s, "m") {
		v, _ := strconv.ParseFloat(strings.TrimSuffix(s, "m"), 64)
		return v / 1e3
	}
	v, _ := strconv.ParseFloat(s, 64)
	return v
}

var memSuffixes = []struct {
	suffix string
	mult   float64
}{
	{"Ki", 1 << 10}, {"Mi", 1 << 20}, {"Gi", 1 << 30}, {"Ti", 1 << 40},
	{"K", 1e3}, {"M", 1e6}, {"G", 1e9}, {"T", 1e12},
}

func parseMem(s string) float64 {
	for _, m := range memSuffixes {
		if strings.HasSuffix(s, m.suffix) {
			v, _ := strconv.ParseFloat(strings.TrimSuffix(s, m.suffix), 64)
			return v * m.mult
		}
	}
	v, _ := strconv.ParseFloat(s, 64)
	return v
}

func pct(used, total float64) float64 {
	if total <= 0 {
		return 0
	}
	return used / total * 100
}

func (k *kubeClient) stats() clusterStats {
	var out clusterStats

	var nodes struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Status struct {
				Allocatable map[string]string `json:"allocatable"`
				Conditions  []struct {
					Type   string `json:"type"`
					Status string `json:"status"`
				} `json:"conditions"`
				NodeInfo struct {
					KubeletVersion string `json:"kubeletVersion"`
				} `json:"nodeInfo"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := k.get(nodesPath, &nodes); err != nil {
		out.Err = err.Error()
		return out
	}

	// Index, not pointer: append reallocates the backing array, and a pointer
	// taken before that would silently absorb the usage writes below.
	byName := map[string]int{}
	for _, n := range nodes.Items {
		s := nodeStat{
			Name:     n.Metadata.Name,
			CPUTotal: parseCPU(n.Status.Allocatable["cpu"]),
			MemTotal: parseMem(n.Status.Allocatable["memory"]),
			Kubelet:  n.Status.NodeInfo.KubeletVersion,
		}
		if p, err := strconv.Atoi(n.Status.Allocatable["pods"]); err == nil {
			s.PodTotal = p
		}
		for _, c := range n.Status.Conditions {
			if c.Type == "Ready" && c.Status == "True" {
				s.Ready = true
			}
		}
		out.Nodes = append(out.Nodes, s)
		byName[s.Name] = len(out.Nodes) - 1
	}

	// Usage is best-effort: if metrics-server is down the node list and pod
	// counts are still worth rendering, just without the CPU/memory bars.
	var usage struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Usage map[string]string `json:"usage"`
		} `json:"items"`
	}
	if err := k.get(nodeMetric, &usage); err != nil {
		out.Err = "metrics-server unavailable: " + err.Error()
	} else {
		for _, u := range usage.Items {
			if i, ok := byName[u.Metadata.Name]; ok {
				out.Nodes[i].CPUUsed = parseCPU(u.Usage["cpu"])
				out.Nodes[i].MemUsed = parseMem(u.Usage["memory"])
			}
		}
	}

	var pods struct {
		Items []struct {
			Spec struct {
				NodeName string `json:"nodeName"`
			} `json:"spec"`
			Status struct {
				Phase string `json:"phase"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := k.get(podsPath, &pods); err == nil {
		out.PodsTotal = len(pods.Items)
		for _, p := range pods.Items {
			if p.Status.Phase == "Running" {
				out.PodsRunning++
			}
			if i, ok := byName[p.Spec.NodeName]; ok {
				out.Nodes[i].PodCount++
			}
		}
	}

	for i := range out.Nodes {
		s := &out.Nodes[i]
		s.CPUPercent = pct(s.CPUUsed, s.CPUTotal)
		s.MemPercent = pct(s.MemUsed, s.MemTotal)
		if s.Ready {
			out.NodesReady++
		}
		out.CPUUsed += s.CPUUsed
		out.CPUTotal += s.CPUTotal
		out.MemUsed += s.MemUsed
		out.MemTotal += s.MemTotal
	}
	return out
}
