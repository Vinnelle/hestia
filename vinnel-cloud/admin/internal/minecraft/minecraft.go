package minecraft

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"
	"vinnel-cloud-admin/internal/kube"
)

const (
	minecraftNamespace  = "server"
	minecraftDeployment = "minecraft"
	minecraftLabel      = "app=minecraft"
	minecraftContainer  = "minecraft"

	minecraftDialTimeout = 5 * time.Second
	minecraftMaxCommand  = 512
	rconMaxPacket        = 4 * 1024 * 1024
	rconDrainWindow      = 300 * time.Millisecond
)

type Status struct {
	Pod     *kube.PodSummary `json:"pod,omitempty"`
	PodErr  string           `json:"podErr,omitempty"`
	Ping    *Ping            `json:"ping,omitempty"`
	PingErr string           `json:"pingErr,omitempty"`
	Address string           `json:"address"`
	Desired *int32           `json:"desired,omitempty"`
}

type Service struct {
	Kube         *kube.Client
	Host         string
	Port         int
	Address      string
	RconAddr     string
	RconPassword string
}

func (m *Service) Status() Status {
	out := Status{Address: m.Address}

	if m.Kube == nil {
		out.PodErr = "kubernetes API unavailable"
	} else {
		if desired, err := m.Kube.DeploymentDesired(minecraftNamespace, minecraftDeployment); err == nil {
			out.Desired = &desired
		}
		if pod, err := m.Kube.PodByLabel(minecraftNamespace, minecraftLabel); err != nil {
			out.PodErr = err.Error()
		} else {
			out.Pod = &pod
		}
	}

	if m.Host == "" {
		out.PingErr = "MINECRAFT_HOST not configured"
	} else if ping, err := pingMinecraft(m.Host, m.Port); err != nil {
		out.PingErr = err.Error()
	} else {
		out.Ping = ping
	}

	return out
}

func (m *Service) LogStream(ctx context.Context, lines int) (io.ReadCloser, error) {
	if m.Kube == nil {
		return nil, errors.New("kubernetes API unavailable")
	}
	pod, err := m.Kube.PodByLabel(minecraftNamespace, minecraftLabel)
	if err != nil {
		return nil, err
	}
	return m.Kube.PodLogStream(ctx, minecraftNamespace, pod.Name, minecraftContainer, lines)
}

// Start and Stop scale the Deployment itself (1 or 0 replicas) — the "free
// the node's RAM" control, distinct from the in-game `stop` RCON command,
// which just restarts the pod since the Deployment's desired count never
// changes under it.
func (m *Service) Start() error {
	if m.Kube == nil {
		return errors.New("kubernetes API unavailable")
	}
	return m.Kube.ScaleDeployment(minecraftNamespace, minecraftDeployment, 1)
}

func (m *Service) Stop() error {
	if m.Kube == nil {
		return errors.New("kubernetes API unavailable")
	}
	return m.Kube.ScaleDeployment(minecraftNamespace, minecraftDeployment, 0)
}

// command opens a fresh RCON connection per command. Reconnecting costs one
// round trip and removes any need to detect and recover a session dropped by a
// server restart between two commands typed minutes apart.
func (m *Service) Command(cmd string) (string, error) {
	cmd = strings.TrimSpace(cmd)
	if cmd == "" {
		return "", errors.New("empty command")
	}
	if len(cmd) > minecraftMaxCommand {
		return "", fmt.Errorf("command longer than %d bytes", minecraftMaxCommand)
	}
	if strings.ContainsAny(cmd, "\n\r\x00") {
		return "", errors.New("command contains a control character")
	}
	conn, err := rconDial(m.RconAddr, m.RconPassword)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	return conn.exec(strings.TrimPrefix(cmd, "/"))
}
