package kube

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
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}}
	return &Client{
		host:  "https://" + host + ":" + port,
		token: strings.TrimSpace(string(token)),
		http:  &http.Client{Timeout: 10 * time.Second, Transport: transport},
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
