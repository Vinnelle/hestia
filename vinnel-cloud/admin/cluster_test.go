package main

import "testing"

func TestParseQuantities(t *testing.T) {
	cpu := []struct {
		in   string
		want float64
	}{
		{"2", 2}, {"1500m", 1.5}, {"250m", 0.25},
		{"123456789n", 0.123456789}, {"1500u", 0.0015}, {"", 0},
	}
	for _, c := range cpu {
		if got := parseCPU(c.in); got != c.want {
			t.Errorf("parseCPU(%q) = %v, want %v", c.in, got, c.want)
		}
	}

	mem := []struct {
		in   string
		want float64
	}{
		{"16008812Ki", 16008812 * 1024}, {"512Mi", 512 * 1024 * 1024},
		{"2Gi", 2 * 1024 * 1024 * 1024}, {"1000000", 1000000}, {"", 0},
	}
	for _, m := range mem {
		if got := parseMem(m.in); got != m.want {
			t.Errorf("parseMem(%q) = %v, want %v", m.in, got, m.want)
		}
	}

	if got := pct(0, 0); got != 0 {
		t.Errorf("pct(0,0) = %v, want 0 (a node reporting no capacity must not divide by zero)", got)
	}
	if got := pct(1, 4); got != 25 {
		t.Errorf("pct(1,4) = %v, want 25", got)
	}
}
