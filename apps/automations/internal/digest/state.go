package digest

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"time"

	"automations/internal/kube"
)

const stateKey = "state.json"

type Snapshot struct {
	SentAt     time.Time           `json:"sent_at"`
	Images     map[string][]string `json:"images"`
	Talos      string              `json:"talos"`
	Kubernetes string              `json:"kubernetes"`
	Critical   int                 `json:"critical"`
	High       int                 `json:"high"`
}

type configMap struct {
	APIVersion string            `json:"apiVersion"`
	Kind       string            `json:"kind"`
	Metadata   map[string]any    `json:"metadata"`
	Data       map[string]string `json:"data"`
}

type State struct {
	Kube      *kube.Client
	Namespace string
	Name      string
}

func (s *State) path() string {
	return "/api/v1/namespaces/" + url.PathEscape(s.Namespace) + "/configmaps/" + url.PathEscape(s.Name)
}

func (s *State) Load(ctx context.Context) (Snapshot, error) {
	var cm configMap
	if err := s.Kube.Get(ctx, s.path(), &cm); err != nil {
		if errors.Is(err, kube.ErrNotFound) {
			return Snapshot{}, fmt.Errorf("state ConfigMap %s/%s is missing: %w", s.Namespace, s.Name, err)
		}
		return Snapshot{}, err
	}
	raw := cm.Data[stateKey]
	if raw == "" {
		return Snapshot{}, nil
	}
	var snap Snapshot
	if err := json.Unmarshal([]byte(raw), &snap); err != nil {
		return Snapshot{}, fmt.Errorf("state ConfigMap %s/%s: %w", s.Namespace, s.Name, err)
	}
	return snap, nil
}

func (s *State) Save(ctx context.Context, snap Snapshot) error {
	var cm configMap
	if err := s.Kube.Get(ctx, s.path(), &cm); err != nil {
		return err
	}
	raw, err := json.Marshal(snap)
	if err != nil {
		return err
	}
	if cm.Data == nil {
		cm.Data = map[string]string{}
	}
	cm.Data[stateKey] = string(raw)
	return s.Kube.Put(ctx, s.path(), cm, nil)
}
