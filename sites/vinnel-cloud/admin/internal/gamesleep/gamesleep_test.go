package gamesleep

import (
	"testing"
	"time"
)

func TestDecide(t *testing.T) {
	now := time.Date(2026, 8, 26, 12, 0, 0, 0, time.UTC)
	timeout := 15 * time.Minute

	if stop, next := Decide(1, now.Add(-time.Hour), now, timeout); stop || !next.IsZero() {
		t.Errorf("Decide with a player online = (%v, %v), want (false, zero) — a populated server must never be scaled away", stop, next)
	}

	stop, next := Decide(0, time.Time{}, now, timeout)
	if stop || !next.Equal(now) {
		t.Errorf("Decide on the first empty poll = (%v, %v), want (false, %v) — emptiness starts the clock, it does not stop the server", stop, next, now)
	}

	stop, next = Decide(0, now.Add(-timeout+time.Second), now, timeout)
	if stop {
		t.Errorf("Decide one second short of the timeout = stop, want no stop (idleSince %v)", next)
	}

	if stop, _ := Decide(0, now.Add(-timeout), now, timeout); !stop {
		t.Error("Decide exactly at the timeout = no stop, want stop")
	}

	if stop, next := Decide(0, now.Add(-time.Hour), now, 0); stop || !next.IsZero() {
		t.Errorf("Decide with timeout 0 = (%v, %v), want (false, zero) — a zero timeout disables sleeping", stop, next)
	}
}
