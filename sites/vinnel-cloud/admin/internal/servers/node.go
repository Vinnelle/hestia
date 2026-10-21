package servers

import (
	"sort"

	"vinnel-cloud-admin/internal/kube"
)

const (
	nodeID          = "hestia"
	podsPath        = "/api/v1/pods"
	podMetricsPath  = "/apis/metrics.k8s.io/v1beta1/pods"
	namespacesGroup = "Namespaces"
)

type podList struct {
	Items []struct {
		Metadata struct {
			Namespace string `json:"namespace"`
		} `json:"metadata"`
		Status struct {
			Phase             string `json:"phase"`
			ContainerStatuses []struct {
				RestartCount int `json:"restartCount"`
				State        struct {
					Waiting *struct {
						Reason string `json:"reason"`
					} `json:"waiting"`
				} `json:"state"`
			} `json:"containerStatuses"`
		} `json:"status"`
	} `json:"items"`
}

type podMetricsList struct {
	Items []struct {
		Metadata struct {
			Namespace string `json:"namespace"`
		} `json:"metadata"`
		Containers []struct {
			Usage map[string]string `json:"usage"`
		} `json:"containers"`
	} `json:"items"`
}

func (c *Collector) collectNode() Server {
	s := Server{ID: nodeID, Name: nodeID, Role: "Talos node", Location: c.NodeLocation}
	if c.Kube == nil || c.ClusterStats == nil {
		s.Status = "unreachable"
		s.Err = "kubernetes API unavailable"
		return s
	}

	st := c.ClusterStats()
	s.Err = st.Err
	s.Up = st.NodesReady > 0
	s.Status = "not ready"
	if s.Up {
		s.Status = "ready"
	}
	var podCount, podCapacity int
	for _, n := range st.Nodes {
		podCount += n.PodCount
		podCapacity += n.PodTotal
	}
	s.Stats = []Stat{
		{Label: "CPU", Value: st.CPUUsed, Max: st.CPUTotal, Unit: "cores"},
		{Label: "Memory", Value: st.MemUsed, Max: st.MemTotal, Unit: "bytes"},
		{Label: "Pods", Value: float64(podCount), Max: float64(podCapacity), Unit: "count"},
		{Label: "Volumes", Value: st.VolumeBytes, Unit: "bytes"},
	}

	var pods podList
	if err := c.Kube.Get(podsPath, &pods); err != nil {
		if s.Err == "" {
			s.Err = err.Error()
		}
		return s
	}
	var usage podMetricsList
	if err := c.Kube.Get(podMetricsPath, &usage); err != nil && s.Err == "" {
		s.Err = "metrics-server unavailable: " + err.Error()
	}
	s.Apps = namespaceApps(pods, usage)
	return s
}

func namespaceApps(pods podList, usage podMetricsList) []App {
	type tally struct {
		running, live, restarts int
		cpu, mem                float64
		bad                     bool
	}
	byNamespace := map[string]*tally{}
	get := func(ns string) *tally {
		t := byNamespace[ns]
		if t == nil {
			t = &tally{}
			byNamespace[ns] = t
		}
		return t
	}

	for _, p := range pods.Items {
		t := get(p.Metadata.Namespace)
		switch p.Status.Phase {
		case "Succeeded":
			continue
		case "Running":
			t.running++
		default:
			t.bad = true
		}
		t.live++
		for _, cs := range p.Status.ContainerStatuses {
			t.restarts += cs.RestartCount
			if cs.State.Waiting != nil && cs.State.Waiting.Reason == "CrashLoopBackOff" {
				t.bad = true
			}
		}
	}
	for _, m := range usage.Items {
		t := get(m.Metadata.Namespace)
		for _, c := range m.Containers {
			t.cpu += kube.ParseCPU(c.Usage["cpu"])
			t.mem += kube.ParseMem(c.Usage["memory"])
		}
	}

	apps := make([]App, 0, len(byNamespace))
	for ns, t := range byNamespace {
		apps = append(apps, App{
			Group: namespacesGroup,
			Name:  ns,
			OK:    !t.bad,
			Stats: []Stat{
				{Label: "CPU", Value: t.cpu, Unit: "cores"},
				{Label: "Memory", Value: t.mem, Unit: "bytes"},
				{Label: "Pods", Value: float64(t.running), Max: float64(t.live), Unit: "count"},
				{Label: "Restarts", Value: float64(t.restarts), Unit: "count"},
			},
		})
	}
	sort.Slice(apps, func(i, j int) bool {
		if a, b := apps[i].Stats[1].Value, apps[j].Stats[1].Value; a != b {
			return a > b
		}
		return apps[i].Name < apps[j].Name
	})
	return apps
}
