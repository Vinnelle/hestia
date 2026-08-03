package satisfactory

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
	"vinnel-cloud-admin/internal/kube"
)

const (
	satisfactoryNamespace = "server"
	satisfactoryLabel     = "app=satisfactory"
	satisfactoryContainer = "satisfactory"
)

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

type remoteSaveFile struct {
	Name string
	URL  string
}

// latestSaveFile lists baseURL (an nginx `autoindex_format json;` directory
// listing) and picks the most recently modified .sav entry.
func latestSaveFile(baseURL string) (remoteSaveFile, error) {
	base := strings.TrimRight(baseURL, "/")
	resp, err := http.Get(base + "/")
	if err != nil {
		return remoteSaveFile{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return remoteSaveFile{}, fmt.Errorf("GET %s/: %s", base, resp.Status)
	}
	var entries []struct {
		Name  string `json:"name"`
		Type  string `json:"type"`
		MTime string `json:"mtime"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&entries); err != nil {
		return remoteSaveFile{}, err
	}
	var best remoteSaveFile
	var bestMod time.Time
	for _, e := range entries {
		if e.Type != "file" || !strings.HasSuffix(e.Name, ".sav") {
			continue
		}
		t, err := time.Parse(http.TimeFormat, e.MTime)
		if err != nil {
			continue
		}
		if best.Name == "" || t.After(bestMod) {
			best = remoteSaveFile{Name: e.Name, URL: base + "/" + e.Name}
			bestMod = t
		}
	}
	if best.Name == "" {
		return remoteSaveFile{}, fmt.Errorf("no .sav files at %s", base)
	}
	return best, nil
}

type Status struct {
	Pod     *kube.PodSummary     `json:"pod,omitempty"`
	PodErr  string               `json:"podErr,omitempty"`
	API     *satisfactoryAPIInfo `json:"api,omitempty"`
	APIErr  string               `json:"apiErr,omitempty"`
	Save    *saveHeader          `json:"save,omitempty"`
	SaveErr string               `json:"saveErr,omitempty"`
}

type Service struct {
	Kube     *kube.Client
	Host     string
	SavesURL string
}

func (s *Service) Status() Status {
	var out Status

	if s.Kube == nil {
		out.PodErr = "kubernetes API unavailable"
	} else if pod, err := s.Kube.PodByLabel(satisfactoryNamespace, satisfactoryLabel); err != nil {
		out.PodErr = err.Error()
	} else {
		out.Pod = &pod
	}

	if s.Host == "" {
		out.APIErr = "SATISFACTORY_HOST not configured"
	} else if api, err := fetchSatisfactoryAPI(s.Host); err != nil {
		out.APIErr = err.Error()
	} else {
		out.API = api
	}

	if sf, err := latestSaveFile(s.SavesURL); err != nil {
		out.SaveErr = err.Error()
	} else if resp, err := http.Get(sf.URL); err != nil {
		out.SaveErr = err.Error()
	} else {
		func() {
			defer resp.Body.Close()
			if resp.StatusCode != http.StatusOK {
				out.SaveErr = fmt.Sprintf("GET %s: %s", sf.URL, resp.Status)
				return
			}
			h, err := parseSaveHeader(resp.Body)
			if err != nil {
				out.SaveErr = err.Error()
				return
			}
			h.FileName = sf.Name
			out.Save = &h
		}()
	}

	return out
}

func (s *Service) Logs(lines int) (string, error) {
	if s.Kube == nil {
		return "", fmt.Errorf("kubernetes API unavailable")
	}
	pod, err := s.Kube.PodByLabel(satisfactoryNamespace, satisfactoryLabel)
	if err != nil {
		return "", err
	}
	return s.Kube.PodLogs(satisfactoryNamespace, pod.Name, satisfactoryContainer, lines)
}

// writeSaveFile streams the latest save through w. Returns an error only if
// nothing has been written to w yet (headers unset).
func (s *Service) WriteSaveFile(w http.ResponseWriter) error {
	sf, err := latestSaveFile(s.SavesURL)
	if err != nil {
		return err
	}
	resp, err := http.Get(sf.URL)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s: %s", sf.URL, resp.Status)
	}
	w.Header().Set("Content-Disposition", `attachment; filename="`+sf.Name+`"`)
	w.Header().Set("Content-Type", "application/octet-stream")
	_, err = io.Copy(w, resp.Body)
	return err
}
