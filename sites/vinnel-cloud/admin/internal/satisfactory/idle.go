package satisfactory

import (
	"context"
	"errors"
	"log"
	"time"

	"vinnel-cloud-admin/internal/gamesleep"
)

const (
	idleDefaultPoll = 60 * time.Second
	idleDefaultIdle = 15 * time.Minute
)

type Idler struct {
	Service     *Service
	IdleTimeout time.Duration
	Poll        time.Duration

	idleSince time.Time
}

func (i *Idler) Run(ctx context.Context) error {
	if i.Service == nil || i.Service.Kube == nil {
		return errors.New("satisfactory idler: kubernetes API unavailable")
	}
	if i.Service.Host == "" {
		return errors.New("satisfactory idler: SATISFACTORY_HOST not configured")
	}
	if i.Poll <= 0 {
		i.Poll = idleDefaultPoll
	}
	if i.IdleTimeout <= 0 {
		i.IdleTimeout = idleDefaultIdle
	}

	ticker := time.NewTicker(i.Poll)
	defer ticker.Stop()
	for {
		i.tick()
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func (i *Idler) tick() {
	desired, err := i.Service.Kube.DeploymentDesired(satisfactoryNamespace, satisfactoryDeployment)
	if err != nil {
		log.Printf("satisfactory idler: desired replicas: %v", err)
		return
	}
	if desired == 0 {
		i.idleSince = time.Time{}
		return
	}

	var token string
	if i.Service.AdminPassword != "" {
		token, _ = i.Service.login()
	}
	api, err := fetchSatisfactoryAPI(i.Service.Host, token)
	if err != nil || api == nil || api.PlayerLimit <= 0 {
		i.idleSince = time.Time{}
		return
	}

	stop, next := gamesleep.Decide(api.ConnectedPlayers, i.idleSince, time.Now(), i.IdleTimeout)
	i.idleSince = next
	if !stop {
		return
	}
	if err := i.Service.Stop(); err != nil {
		log.Printf("satisfactory idler: stop: %v", err)
		return
	}
	log.Printf("satisfactory idler: scaled to 0 after %s with no players", i.IdleTimeout)
}
