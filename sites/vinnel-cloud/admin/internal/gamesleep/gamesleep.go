package gamesleep

import "time"

func Decide(players int, idleSince, now time.Time, timeout time.Duration) (bool, time.Time) {
	if timeout <= 0 || players > 0 {
		return false, time.Time{}
	}
	if idleSince.IsZero() {
		return false, now
	}
	if now.Sub(idleSince) >= timeout {
		return true, time.Time{}
	}
	return false, idleSince
}
