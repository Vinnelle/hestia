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

func newAPIClient(timeout time.Duration) *http.Client {
	return &http.Client{
		Timeout:   timeout,
		Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}},
	}
}

var (
	apiClient     = newAPIClient(5 * time.Second)
	commandClient = newAPIClient(30 * time.Second)
)

func apiCall(client *http.Client, host, token, fn string, data any) (json.RawMessage, error) {
	payload := map[string]any{"function": fn}
	if data != nil {
		payload["data"] = data
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("POST", "https://"+host+":7777/api/v1", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var out struct {
		Data         json.RawMessage `json:"data"`
		ErrorCode    string          `json:"errorCode"`
		ErrorMessage string          `json:"errorMessage"`
	}
	dec := json.NewDecoder(io.LimitReader(resp.Body, 1<<20))
	decErr := dec.Decode(&out)
	if msg := out.ErrorMessage; msg != "" {
		return nil, fmt.Errorf("%s: %s", fn, msg)
	}
	if out.ErrorCode != "" {
		return nil, fmt.Errorf("%s: %s", fn, out.ErrorCode)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%s: %s", fn, resp.Status)
	}
	if decErr != nil {
		return nil, decErr
	}
	if len(out.Data) == 0 {
		return nil, fmt.Errorf("%s: response carried no data", fn)
	}
	return out.Data, nil
}

func fetchSatisfactoryAPI(host, token string) (*satisfactoryAPIInfo, error) {
	if _, err := apiCall(apiClient, host, "", "HealthCheck", map[string]string{"ClientCustomData": ""}); err != nil {
		return nil, err
	}
	info := &satisfactoryAPIInfo{Healthy: true}

	data, err := apiCall(apiClient, host, token, "QueryServerState", nil)
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
	if err := json.Unmarshal(data, &state); err != nil {
		return info, nil
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
	Kube          *kube.Client
	Host          string
	SavesURL      string
	AdminPassword string
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
	} else {
		var token string
		if s.AdminPassword != "" {
			token, _ = s.login()
		}
		if api, err := fetchSatisfactoryAPI(s.Host, token); err != nil {
			out.APIErr = err.Error()
		} else {
			out.API = api
		}
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
