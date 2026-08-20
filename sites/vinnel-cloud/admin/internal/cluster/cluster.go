package cluster

import (
	"strconv"

	"vinnel-cloud-admin/internal/kube"
)

const (
	nodesPath  = "/api/v1/nodes"
	podsPath   = "/api/v1/pods"
	pvcsPath   = "/api/v1/persistentvolumeclaims"
	pvsPath    = "/api/v1/persistentvolumes"
	nodeMetric = "/apis/metrics.k8s.io/v1beta1/nodes"
)

type NodeStat struct {
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

type VolumeStat struct {
	Name      string  `json:"name"`
	Namespace string  `json:"namespace"`
	Claim     string  `json:"claim"`
	Class     string  `json:"class"`
	Phase     string  `json:"phase"`
	Capacity  float64 `json:"capacity"`
}

type Stats struct {
	Nodes       []NodeStat `json:"nodes"`
	NodesReady  int        `json:"nodesReady"`
	PodsRunning int        `json:"podsRunning"`
	PodsTotal   int        `json:"podsTotal"`
	CPUUsed     float64    `json:"cpuUsed"`
	CPUTotal    float64    `json:"cpuTotal"`
	MemUsed     float64    `json:"memUsed"`
	MemTotal    float64    `json:"memTotal"`

	Volumes     []VolumeStat `json:"volumes"`
	VolumeBytes float64      `json:"volumeBytes"`

	Err string `json:"err,omitempty"`
}

// Collect gathers one snapshot of node, pod and volume state.
func Collect(k *kube.Client) Stats {
	var out Stats

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
	if err := k.Get(nodesPath, &nodes); err != nil {
		out.Err = err.Error()
		return out
	}

	byName := map[string]int{}
	for _, n := range nodes.Items {
		s := NodeStat{
			Name:     n.Metadata.Name,
			CPUTotal: kube.ParseCPU(n.Status.Allocatable["cpu"]),
			MemTotal: kube.ParseMem(n.Status.Allocatable["memory"]),
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
	if err := k.Get(nodeMetric, &usage); err != nil {
		out.Err = "metrics-server unavailable: " + err.Error()
	} else {
		for _, u := range usage.Items {
			if i, ok := byName[u.Metadata.Name]; ok {
				out.Nodes[i].CPUUsed = kube.ParseCPU(u.Usage["cpu"])
				out.Nodes[i].MemUsed = kube.ParseMem(u.Usage["memory"])
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
	if err := k.Get(podsPath, &pods); err == nil {
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

func (out *Stats) storage(k *kube.Client) {
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
	if err := k.Get(pvcsPath, &pvcs); err == nil {
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
	if err := k.Get(pvsPath, &pvs); err != nil {
		return
	}
	for _, p := range pvs.Items {
		size := kube.ParseMem(p.Spec.Capacity["storage"])
		class := p.Spec.StorageClassName
		if class == "" {
			class = claimClass[claimKey{p.Spec.ClaimRef.Namespace, p.Spec.ClaimRef.Name}]
		}
		out.Volumes = append(out.Volumes, VolumeStat{
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

func pct(used, total float64) float64 {
	if total <= 0 {
		return 0
	}
	return used / total * 100
}
