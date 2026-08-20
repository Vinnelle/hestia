package kube

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
		if got := ParseCPU(c.in); got != c.want {
			t.Errorf("ParseCPU(%q) = %v, want %v", c.in, got, c.want)
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
		if got := ParseMem(m.in); got != m.want {
			t.Errorf("ParseMem(%q) = %v, want %v", m.in, got, m.want)
		}
	}
}
