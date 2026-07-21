package main

import "testing"

func TestGravatarURL(t *testing.T) {
	// sha256("a@vin.moe"), normalization of case + whitespace
	want := "https://www.gravatar.com/avatar/f8306a75bcca21dc2fd181916a1df7efb5651f0bdea9dd32cc7c4efa0ca78693?d=mp"
	if got := gravatarURL("  A@vin.moe "); got != want {
		t.Errorf("got %s", got)
	}
}
