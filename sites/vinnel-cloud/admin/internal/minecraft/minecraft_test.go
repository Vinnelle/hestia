package minecraft

import (
	"strings"
	"testing"
)

func TestCommandValidation(t *testing.T) {
	m := &Service{RconAddr: "127.0.0.1:1", RconPassword: "pw"}
	cases := map[string]string{
		"empty":         "   ",
		"newline":       "say hi\nstop",
		"null byte":     "say \x00",
		"over max size": strings.Repeat("x", minecraftMaxCommand+1),
	}
	for name, cmd := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := m.Command(cmd); err == nil {
				t.Fatalf("want error for %q, got nil", name)
			}
		})
	}
}

func TestCommandRequiresConfiguration(t *testing.T) {
	if _, err := (&Service{RconPassword: "pw"}).Command("list"); err == nil {
		t.Fatal("want error for missing RCON address, got nil")
	}
	if _, err := (&Service{RconAddr: "127.0.0.1:1"}).Command("list"); err == nil {
		t.Fatal("want error for missing RCON password, got nil")
	}
}

func TestStatusReportsErrorsWithoutKube(t *testing.T) {
	s := (&Service{Address: "mc.vin.moe"}).Status()
	if s.PodErr == "" || s.PingErr == "" {
		t.Errorf("want both errors populated, got %+v", s)
	}
	if s.Address != "mc.vin.moe" {
		t.Errorf("address = %q", s.Address)
	}
}
