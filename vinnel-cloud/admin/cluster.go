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

const (
	saDir      = "/var/run/secrets/kubernetes.io/serviceaccount"
	nodesPath  = "/api/v1/nodes"
	podsPath   = "/api/v1/pods"
	pvcsPath   = "/api/v1/persistentvolumeclaims"
	pvsPath    = "/api/v1/persistentvolumes"
	nodeMetric = "/apis/metrics.k8s.io/v1beta1/nodes"
	cephPath   = "/apis/ceph.rook.io/v1/namespaces/rook-ceph/cephclusters"
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

type volumeStat struct {
	Name      string  `json:"name"`
	Namespace string  `json:"namespace"`
	Claim     string  `json:"claim"`
	Class     string  `json:"class"`
	Phase     string  `json:"phase"`
	Capacity  float64 `json:"capacity"`
}

type cephStat struct {
	Available float64 `json:"available"`
	Used      float64 `json:"used"`
	Total     float64 `json:"total"`
	Health    string  `json:"health"`
	Present   bool    `json:"present"`
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

	Ceph        cephStat     `json:"ceph"`
	Volumes     []volumeStat `json:"volumes"`
	VolumeBytes float64      `json:"volumeBytes"`

	Err string `json:"err,omitempty"`
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

	out.storage(k)

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

func (out *clusterStats) storage(k *kubeClient) {
	var cephList struct {
		Items []struct {
			Status struct {
				Ceph struct {
					Health   string `json:"health"`
					Capacity struct {
						BytesAvailable float64 `json:"bytesAvailable"`
						BytesUsed      float64 `json:"bytesUsed"`
						BytesTotal     float64 `json:"bytesTotal"`
					} `json:"capacity"`
				} `json:"ceph"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := k.get(cephPath, &cephList); err == nil && len(cephList.Items) > 0 {
		c := cephList.Items[0].Status.Ceph
		out.Ceph = cephStat{
			Available: c.Capacity.BytesAvailable,
			Used:      c.Capacity.BytesUsed,
			Total:     c.Capacity.BytesTotal,
			Health:    c.Health,
			Present:   true,
		}
	}

	type claimKey struct{ ns, name string }
	claimClass := map[claimKey]string{}
	var pvcs struct {
		Items []struct {
			Metadata struct {
				Name      string `json:"name"`
				Namespace string `json:"namespace"`
			} `json:"metadata"`
			Spec struct {
				StorageClassName string `json:"storageClassName"`
			} `json:"spec"`
		} `json:"items"`
	}
	if err := k.get(pvcsPath, &pvcs); err == nil {
		for _, c := range pvcs.Items {
			claimClass[claimKey{c.Metadata.Namespace, c.Metadata.Name}] = c.Spec.StorageClassName
		}
	}

	var pvs struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Spec struct {
				Capacity         map[string]string `json:"capacity"`
				StorageClassName string            `json:"storageClassName"`
				ClaimRef         struct {
					Name      string `json:"name"`
					Namespace string `json:"namespace"`
				} `json:"claimRef"`
			} `json:"spec"`
			Status struct {
				Phase string `json:"phase"`
			} `json:"status"`
		} `json:"items"`
	}
	if err := k.get(pvsPath, &pvs); err != nil {
		return
	}
	for _, p := range pvs.Items {
		size := parseMem(p.Spec.Capacity["storage"])
		class := p.Spec.StorageClassName
		if class == "" {
			class = claimClass[claimKey{p.Spec.ClaimRef.Namespace, p.Spec.ClaimRef.Name}]
		}
		out.Volumes = append(out.Volumes, volumeStat{
			Name:      p.Metadata.Name,
			Namespace: p.Spec.ClaimRef.Namespace,
			Claim:     p.Spec.ClaimRef.Name,
			Class:     class,
			Phase:     p.Status.Phase,
			Capacity:  size,
		})
		out.VolumeBytes += size
	}
}
