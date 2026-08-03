package kube

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const saDir = "/var/run/secrets/kubernetes.io/serviceaccount"

type Client struct {
	host  string
	token string
	http  *http.Client
}

func New() (*Client, error) {
	host := os.Getenv("KUBERNETES_SERVICE_HOST")
	port := os.Getenv("KUBERNETES_SERVICE_PORT")
	if port == "" {
		port = "443"
	}
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
	return &Client{
		host:  "https://" + host + ":" + port,
		token: strings.TrimSpace(string(token)),
		http: &http.Client{
			Timeout:   10 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}},
		},
	}, nil
}

func (k *Client) Get(path string, out any) error {
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

func ParseCPU(s string) float64 {
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

func ParseMem(s string) float64 {
	for _, m := range memSuffixes {
		if strings.HasSuffix(s, m.suffix) {
			v, _ := strconv.ParseFloat(strings.TrimSuffix(s, m.suffix), 64)
			return v * m.mult
		}
	}
	v, _ := strconv.ParseFloat(s, 64)
	return v
}

type PodSummary struct {
	Name      string    `json:"name"`
	Phase     string    `json:"phase"`
	Ready     bool      `json:"ready"`
	Restarts  int32     `json:"restarts"`
	Node      string    `json:"node"`
	Image     string    `json:"image"`
	StartTime time.Time `json:"startTime"`
	CPUUsed   float64   `json:"cpuUsed"`
	MemUsed   float64   `json:"memUsed"`
}

func (k *Client) PodByLabel(ns, labelSelector string) (PodSummary, error) {
	var out PodSummary
	var pods struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Spec struct {
				NodeName string `json:"nodeName"`
			} `json:"spec"`
			Status struct {
				Phase             string `json:"phase"`
				StartTime         string `json:"startTime"`
				ContainerStatuses []struct {
					Ready        bool   `json:"ready"`
					RestartCount int32  `json:"restartCount"`
					Image        string `json:"image"`
				} `json:"containerStatuses"`
			} `json:"status"`
		} `json:"items"`
	}
	path := fmt.Sprintf("/api/v1/namespaces/%s/pods?labelSelector=%s", ns, url.QueryEscape(labelSelector))
	if err := k.Get(path, &pods); err != nil {
		return out, err
	}
	if len(pods.Items) == 0 {
		return out, fmt.Errorf("no pod matching %q in namespace %s", labelSelector, ns)
	}
	p := pods.Items[0]
	out.Name = p.Metadata.Name
	out.Phase = p.Status.Phase
	out.Node = p.Spec.NodeName
	if t, err := time.Parse(time.RFC3339, p.Status.StartTime); err == nil {
		out.StartTime = t
	}
	if len(p.Status.ContainerStatuses) > 0 {
		cs := p.Status.ContainerStatuses[0]
		out.Ready = cs.Ready
		out.Restarts = cs.RestartCount
		out.Image = cs.Image
	}

	var metrics struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Containers []struct {
				Usage map[string]string `json:"usage"`
			} `json:"containers"`
		} `json:"items"`
	}
	metricsPath := fmt.Sprintf("/apis/metrics.k8s.io/v1beta1/namespaces/%s/pods?labelSelector=%s", ns, url.QueryEscape(labelSelector))
	if err := k.Get(metricsPath, &metrics); err == nil {
		for _, m := range metrics.Items {
			if m.Metadata.Name == out.Name && len(m.Containers) > 0 {
				out.CPUUsed = ParseCPU(m.Containers[0].Usage["cpu"])
				out.MemUsed = ParseMem(m.Containers[0].Usage["memory"])
			}
		}
	}
	return out, nil
}

func (k *Client) GetRaw(path string) ([]byte, error) {
	req, err := http.NewRequest("GET", k.host+path, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+k.token)
	resp, err := k.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GET %s: %s", path, resp.Status)
	}
	return io.ReadAll(resp.Body)
}

func (k *Client) PodLogs(ns, pod, container string, tailLines int) (string, error) {
	path := fmt.Sprintf("/api/v1/namespaces/%s/pods/%s/log?container=%s&tailLines=%d&timestamps=true", ns, pod, container, tailLines)
	b, err := k.GetRaw(path)
	if err != nil {
		return "", err
	}
	return string(b), nil
}
