package minecraft

import (
	"bytes"
	"encoding/json"
	"io"
	"net"
	"strings"
	"testing"
)

func readMCPacket(t *testing.T, r io.Reader) (int32, []byte) {
	t.Helper()
	length, err := readVarInt(r)
	if err != nil {
		t.Fatalf("read packet length: %v", err)
	}
	buf := make([]byte, length)
	if _, err := io.ReadFull(r, buf); err != nil {
		t.Fatalf("read packet body: %v", err)
	}
	br := bytes.NewReader(buf)
	id, err := readVarInt(br)
	if err != nil {
		t.Fatalf("read packet id: %v", err)
	}
	rest, _ := io.ReadAll(br)
	return id, rest
}

func TestVarIntRoundTrip(t *testing.T) {
	for _, v := range []int32{0, 1, 2, 127, 128, 255, 2097151, 2147483647, -1, -2147483648} {
		var buf bytes.Buffer
		writeVarInt(&buf, v)
		got, err := readVarInt(&buf)
		if err != nil {
			t.Fatalf("readVarInt(%d): %v", v, err)
		}
		if got != v {
			t.Errorf("varint round trip: want %d, got %d", v, got)
		}
	}
}

func TestReadVarIntRejectsOverlong(t *testing.T) {
	if _, err := readVarInt(bytes.NewReader([]byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff})); err == nil {
		t.Fatal("want error for overlong varint, got nil")
	}
}

func TestChatText(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain string", `"hello"`, "hello"},
		{"text node", `{"text":"hi"}`, "hi"},
		{"nested extra", `{"text":"a","extra":[{"text":"b"},{"text":"c","extra":[{"text":"d"}]}]}`, "abcd"},
		{"array", `[{"text":"x"},{"text":"y"}]`, "xy"},
		{"empty", ``, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := chatText(json.RawMessage(c.in)); got != c.want {
				t.Errorf("chatText(%s) = %q, want %q", c.in, got, c.want)
			}
		})
	}
}

func TestStripFormatting(t *testing.T) {
	if got := stripFormatting("§aCreate§r: §lUltimate§r"); got != "Create: Ultimate" {
		t.Errorf("stripFormatting = %q", got)
	}
	if got := stripFormatting("plain"); got != "plain" {
		t.Errorf("stripFormatting(plain) = %q", got)
	}
}

// fakeMinecraftServer answers one Server List Ping with the supplied JSON.
func fakeMinecraftServer(t *testing.T, statusJSON string) (host string, port int) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { ln.Close() })

	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		readMCPacket(t, conn) // handshake
		readMCPacket(t, conn) // status request
		var payload bytes.Buffer
		writeMCString(&payload, statusJSON)
		conn.Write(mcPacket(0x00, payload.Bytes()))
	}()

	addr := ln.Addr().(*net.TCPAddr)
	return addr.IP.String(), addr.Port
}

func TestPingMinecraft(t *testing.T) {
	host, port := fakeMinecraftServer(t, `{
		"version":{"name":"NeoForge 1.21.1","protocol":767},
		"players":{"max":20,"online":2,"sample":[{"name":"ida"},{"name":"vinnell"}]},
		"description":{"text":"§aCreate: Ultimate Selection 2"}
	}`)

	got, err := pingMinecraft(host, port)
	if err != nil {
		t.Fatalf("pingMinecraft: %v", err)
	}
	if got.Version != "NeoForge 1.21.1" || got.Protocol != 767 {
		t.Errorf("version = %q/%d", got.Version, got.Protocol)
	}
	if got.PlayersOnline != 2 || got.PlayersMax != 20 {
		t.Errorf("players = %d/%d", got.PlayersOnline, got.PlayersMax)
	}
	if strings.Join(got.Players, ",") != "ida,vinnell" {
		t.Errorf("player sample = %v", got.Players)
	}
	if got.MOTD != "Create: Ultimate Selection 2" {
		t.Errorf("motd = %q", got.MOTD)
	}
}

func TestPingMinecraftRefused(t *testing.T) {
	// Port 1 on loopback has nothing listening.
	if _, err := pingMinecraft("127.0.0.1", 1); err == nil {
		t.Fatal("want dial error, got nil")
	}
}
