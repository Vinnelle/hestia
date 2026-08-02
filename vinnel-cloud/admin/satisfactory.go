package main

import (
	"bytes"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf16"
)

const (
	satisfactoryNamespace = "server"
	satisfactoryLabel     = "app=satisfactory"
	satisfactoryContainer = "satisfactory"
)

type podSummary struct {
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

func (k *kubeClient) podByLabel(ns, labelSelector string) (podSummary, error) {
	var out podSummary
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
	if err := k.get(path, &pods); err != nil {
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
	if err := k.get(metricsPath, &metrics); err == nil {
		for _, m := range metrics.Items {
			if m.Metadata.Name == out.Name && len(m.Containers) > 0 {
				out.CPUUsed = parseCPU(m.Containers[0].Usage["cpu"])
				out.MemUsed = parseMem(m.Containers[0].Usage["memory"])
			}
		}
	}
	return out, nil
}

func (k *kubeClient) getRaw(path string) ([]byte, error) {
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

func (k *kubeClient) podLogs(ns, pod, container string, tailLines int) (string, error) {
	path := fmt.Sprintf("/api/v1/namespaces/%s/pods/%s/log?container=%s&tailLines=%d&timestamps=true", ns, pod, container, tailLines)
	b, err := k.getRaw(path)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

type satisfactoryAPIInfo struct {
	Healthy           bool    `json:"healthy"`
	SessionName       string  `json:"sessionName"`
	ConnectedPlayers  int     `json:"connectedPlayers"`
	PlayerLimit       int     `json:"playerLimit"`
	TechTier          int     `json:"techTier"`
	GamePhase         string  `json:"gamePhase"`
	IsGameRunning     bool    `json:"isGameRunning"`
	TotalGameDuration int     `json:"totalGameDurationSeconds"`
	AverageTickRate   float64 `json:"averageTickRate"`
}

func fetchSatisfactoryAPI(host string) (*satisfactoryAPIInfo, error) {
	client := &http.Client{
		Timeout:   5 * time.Second,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}},
	}
	call := func(fn string) (map[string]json.RawMessage, error) {
		body, _ := json.Marshal(map[string]string{"function": fn})
		req, err := http.NewRequest("POST", "https://"+host+":7777/api/v1", bytes.NewReader(body))
		if err != nil {
			return nil, err
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("%s: %s", fn, resp.Status)
		}
		var out struct {
			Data map[string]json.RawMessage `json:"data"`
		}
		if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
			return nil, err
		}
		return out.Data, nil
	}

	if _, err := call("HealthCheck"); err != nil {
		return nil, err
	}
	info := &satisfactoryAPIInfo{Healthy: true}

	data, err := call("QueryServerState")
	if err != nil {
		return info, nil
	}
	var state struct {
		ServerGameState struct {
			ActiveSessionName   string  `json:"activeSessionName"`
			NumConnectedPlayers int     `json:"numConnectedPlayers"`
			PlayerLimit         int     `json:"playerLimit"`
			TechTier            int     `json:"techTier"`
			GamePhase           string  `json:"gamePhase"`
			IsGameRunning       bool    `json:"isGameRunning"`
			TotalGameDuration   int     `json:"totalGameDuration"`
			AverageTickRate     float64 `json:"averageTickRate"`
		} `json:"serverGameState"`
	}
	if raw, ok := data["serverGameState"]; ok {
		_ = json.Unmarshal(raw, &state)
	}
	info.SessionName = state.ServerGameState.ActiveSessionName
	info.ConnectedPlayers = state.ServerGameState.NumConnectedPlayers
	info.PlayerLimit = state.ServerGameState.PlayerLimit
	info.TechTier = state.ServerGameState.TechTier
	info.GamePhase = state.ServerGameState.GamePhase
	info.IsGameRunning = state.ServerGameState.IsGameRunning
	info.TotalGameDuration = state.ServerGameState.TotalGameDuration
	info.AverageTickRate = state.ServerGameState.AverageTickRate
	return info, nil
}

type saveHeader struct {
	FileName         string    `json:"fileName"`
	SaveVersion      uint32    `json:"saveVersion"`
	BuildVersion     uint32    `json:"buildVersion"`
	MapName          string    `json:"mapName"`
	SessionName      string    `json:"sessionName"`
	PlayDurationSecs uint32    `json:"playDurationSeconds"`
	SavedAt          time.Time `json:"savedAt"`
	IsCreativeModeOn bool      `json:"isCreativeModeEnabled"`
}

const dotnetEpochToUnixTicks = 621355968000000000

const maxSaveStringBytes = 1 << 20

type byteReader struct {
	r   io.Reader
	err error
}

func (b *byteReader) read(buf []byte) {
	if b.err != nil {
		return
	}
	_, b.err = io.ReadFull(b.r, buf)
}

func (b *byteReader) uint8() uint8 {
	var buf [1]byte
	b.read(buf[:])
	return buf[0]
}

func (b *byteReader) int8() int8 { return int8(b.uint8()) }

func (b *byteReader) uint32() uint32 {
	var buf [4]byte
	b.read(buf[:])
	return binary.LittleEndian.Uint32(buf[:])
}

func (b *byteReader) int32() int32 { return int32(b.uint32()) }

func (b *byteReader) uint64() uint64 {
	var buf [8]byte
	b.read(buf[:])
	return binary.LittleEndian.Uint64(buf[:])
}

func (b *byteReader) string() string {
	n := b.int32()
	if b.err != nil || n == 0 {
		return ""
	}
	if n > 0 {
		if n > maxSaveStringBytes {
			b.err = fmt.Errorf("string length %d exceeds sanity limit", n)
			return ""
		}
		buf := make([]byte, n)
		b.read(buf)
		if b.err != nil || n == 0 {
			return ""
		}
		return string(buf[:n-1])
	}
	count := int(-n)
	if count*2 > maxSaveStringBytes {
		b.err = fmt.Errorf("string length %d exceeds sanity limit", count)
		return ""
	}
	buf := make([]byte, count*2)
	b.read(buf)
	if b.err != nil || count <= 1 {
		return ""
	}
	units := make([]uint16, count-1)
	for i := range units {
		units[i] = binary.LittleEndian.Uint16(buf[i*2:])
	}
	return string(utf16.Decode(units))
}

func parseSaveHeader(r io.Reader) (saveHeader, error) {
	var h saveHeader
	b := &byteReader{r: r}

	saveHeaderType := b.uint32()
	if b.err == nil && saveHeaderType != 13 && saveHeaderType != 14 {
		return h, fmt.Errorf("unsupported save header type %d", saveHeaderType)
	}
	saveVersion := b.uint32()
	h.SaveVersion = saveVersion
	h.BuildVersion = b.uint32()
	if saveVersion >= 14 {
		b.string()
	}
	h.MapName = b.string()
	b.string()
	h.SessionName = b.string()
	h.PlayDurationSecs = b.uint32()
	ticks := b.uint64()
	if b.err == nil {
		h.SavedAt = time.Unix(0, (int64(ticks)-dotnetEpochToUnixTicks)*100).UTC()
	}
	b.int8()
	if saveVersion >= 7 {
		b.uint32()
	}
	if saveVersion >= 8 {
		b.string()
	}
	b.uint32()
	if saveVersion >= 10 {
		b.string()
	}
	if saveVersion >= 13 {
		b.uint32()
		b.uint32()
		b.uint64()
		b.uint64()
		h.IsCreativeModeOn = b.uint32() != 0
	}
	if b.err != nil {
		return saveHeader{}, b.err
	}
	return h, nil
}

func latestSaveFile(dir string) (string, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return "", err
	}
	var best string
	var bestMod time.Time
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".sav") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if best == "" || info.ModTime().After(bestMod) {
			best = e.Name()
			bestMod = info.ModTime()
		}
	}
	if best == "" {
		return "", fmt.Errorf("no .sav files in %s", dir)
	}
	return filepath.Join(dir, best), nil
}

type satisfactoryStatus struct {
	Pod     *podSummary          `json:"pod,omitempty"`
	PodErr  string               `json:"podErr,omitempty"`
	API     *satisfactoryAPIInfo `json:"api,omitempty"`
	APIErr  string               `json:"apiErr,omitempty"`
	Save    *saveHeader          `json:"save,omitempty"`
	SaveErr string               `json:"saveErr,omitempty"`
}

type satisfactoryService struct {
	kube     *kubeClient
	host     string
	savesDir string
}

func (s *satisfactoryService) status() satisfactoryStatus {
	var out satisfactoryStatus

	if s.kube == nil {
		out.PodErr = "kubernetes API unavailable"
	} else if pod, err := s.kube.podByLabel(satisfactoryNamespace, satisfactoryLabel); err != nil {
		out.PodErr = err.Error()
	} else {
		out.Pod = &pod
	}

	if s.host == "" {
		out.APIErr = "SATISFACTORY_HOST not configured"
	} else if api, err := fetchSatisfactoryAPI(s.host); err != nil {
		out.APIErr = err.Error()
	} else {
		out.API = api
	}

	if path, err := latestSaveFile(s.savesDir); err != nil {
		out.SaveErr = err.Error()
	} else if f, err := os.Open(path); err != nil {
		out.SaveErr = err.Error()
	} else {
		h, err := parseSaveHeader(f)
		f.Close()
		if err != nil {
			out.SaveErr = err.Error()
		} else {
			h.FileName = filepath.Base(path)
			out.Save = &h
		}
	}

	return out
}

func (s *satisfactoryService) logs(lines int) (string, error) {
	if s.kube == nil {
		return "", fmt.Errorf("kubernetes API unavailable")
	}
	pod, err := s.kube.podByLabel(satisfactoryNamespace, satisfactoryLabel)
	if err != nil {
		return "", err
	}
	return s.kube.podLogs(satisfactoryNamespace, pod.Name, satisfactoryContainer, lines)
}

func (s *satisfactoryService) saveFilePath() (string, error) {
	return latestSaveFile(s.savesDir)
}
