package digest

import (
	"context"
	"fmt"
	"log"
	"time"

	"automations/internal/llm"
)

type Digest struct {
	Collector *Collector
	LLM       *llm.Client
	State     *State
	Mailer    *Resend
	From      string
	To        []string
	Location  *time.Location
	AdminURL  string
	Job       string
	Now       func() time.Time
}

func (d *Digest) Run(ctx context.Context) error {
	now := time.Now
	if d.Now != nil {
		now = d.Now
	}
	prev, err := d.State.Load(ctx)
	if err != nil {
		return err
	}
	to := now().UTC().Truncate(time.Minute)
	from := prev.SentAt
	if from.IsZero() || !from.Before(to) {
		from = to.Add(-24 * time.Hour)
	}

	facts, workloads := d.Collector.Collect(ctx, from, to, prev)
	checks := Checks(facts)
	summary, err := Summarize(ctx, d.LLM, facts, checks)
	if err != nil {
		log.Printf("digest summary: %v", err)
		summary = Fallback(checks, err)
	}

	view := Build(facts, summary, checks, d.Location, d.AdminURL)
	html, err := Render(view)
	if err != nil {
		return err
	}
	key := d.Job
	if key == "" {
		key = "digest-" + to.In(d.Location).Format("2006-01-02")
	}
	id, err := d.Mailer.Send(ctx, Email{
		From:    d.From,
		To:      d.To,
		Subject: Subject(summary, to.In(d.Location)),
		HTML:    html,
		Text:    Text(view),
	}, key)
	if err != nil {
		return err
	}
	log.Printf("digest sent: id=%s status=%s window=%s..%s checks=%d gaps=%d bytes=%d", id, summary.Status, from.Format(time.RFC3339), to.Format(time.RFC3339), len(checks), len(facts.Gaps), len(html))

	next := Snapshot{
		SentAt:     to,
		Images:     workloads,
		Talos:      facts.Cluster.Talos,
		Kubernetes: facts.Cluster.Kubernetes,
		Critical:   facts.Security.Critical,
		High:       facts.Security.High,
	}
	if next.Images == nil {
		next.Images = prev.Images
	}
	if err := d.State.Save(ctx, next); err != nil {
		return fmt.Errorf("digest sent but its state was not saved, so tomorrow's window starts at %s: %w", from.Format(time.RFC3339), err)
	}
	return nil
}
