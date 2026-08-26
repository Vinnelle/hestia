package minecraft

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"net"
	"testing"
	"time"
)

func handshakePacket(protocol int32, host string, port uint16, next int32) []byte {
	var hs bytes.Buffer
	writeVarInt(&hs, protocol)
	writeMCString(&hs, host)
	binary.Write(&hs, binary.BigEndian, port)
	writeVarInt(&hs, next)
	return mcPacket(0x00, hs.Bytes())
}

func packetString(t *testing.T, body []byte) string {
	t.Helper()
	r := bytes.NewReader(body)
	length, err := readVarInt(r)
	if err != nil {
		t.Fatalf("read string length: %v", err)
	}
	out := make([]byte, length)
	if _, err := r.Read(out); err != nil {
		t.Fatalf("read string body: %v", err)
	}
	return string(out)
}

func TestReadSleeperHandshake(t *testing.T) {
	for _, tc := range []struct {
		name     string
		protocol int32
		next     int32
	}{
		{"status", 767, sleeperStateStatus},
		{"login", 770, sleeperStateLogin},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := bytes.NewReader(handshakePacket(tc.protocol, "mc.vin.moe", 25565, tc.next))
			protocol, next, err := readSleeperHandshake(r)
			if err != nil {
				t.Fatalf("readSleeperHandshake: %v", err)
			}
			if protocol != tc.protocol || next != tc.next {
				t.Errorf("readSleeperHandshake = (%d, %d), want (%d, %d) — misreading the next state sends a joining player the status reply and never wakes the server", protocol, next, tc.protocol, tc.next)
			}
		})
	}
}

func TestServeStatusAnswersAndPongs(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()

	s := &Sleeper{MOTD: "zzz"}
	go func() {
		defer server.Close()
		s.serveStatus(server, 767)
	}()

	client.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := client.Write(mcPacket(0x00, nil)); err != nil {
		t.Fatalf("write status request: %v", err)
	}

	id, body, err := readSleeperPacket(client)
	if err != nil {
		t.Fatalf("read status response: %v", err)
	}
	if id != 0x00 {
		t.Fatalf("status response id = %d, want 0", id)
	}

	var payload struct {
		Version struct {
			Protocol int32 `json:"protocol"`
		} `json:"version"`
		Description struct {
			Text string `json:"text"`
		} `json:"description"`
	}
	if err := json.Unmarshal([]byte(packetString(t, body)), &payload); err != nil {
		t.Fatalf("decode status JSON: %v", err)
	}
	if payload.Description.Text != "zzz" {
		t.Errorf("status MOTD = %q, want %q — the server list is the only place a sleeping server can say it is asleep", payload.Description.Text, "zzz")
	}
	if payload.Version.Protocol != 767 {
		t.Errorf("status protocol = %d, want 767 — echoing the client's protocol keeps the entry from rendering as incompatible", payload.Version.Protocol)
	}

	nonce := []byte{1, 2, 3, 4, 5, 6, 7, 8}
	if _, err := client.Write(mcPacket(0x01, nonce)); err != nil {
		t.Fatalf("write ping: %v", err)
	}
	id, body, err = readSleeperPacket(client)
	if err != nil {
		t.Fatalf("read pong: %v", err)
	}
	if id != 0x01 || !bytes.Equal(body, nonce) {
		t.Errorf("pong = (%d, %v), want (1, %v) — an unanswered ping shows the entry as unreachable instead of asleep", id, body, nonce)
	}
}

func TestWriteLoginDisconnectCarriesTheWakeText(t *testing.T) {
	var buf bytes.Buffer
	if err := writeLoginDisconnect(&buf, "waking"); err != nil {
		t.Fatalf("writeLoginDisconnect: %v", err)
	}
	id, body, err := readSleeperPacket(&buf)
	if err != nil {
		t.Fatalf("read disconnect: %v", err)
	}
	if id != 0x00 {
		t.Fatalf("disconnect id = %d, want 0", id)
	}
	var payload struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal([]byte(packetString(t, body)), &payload); err != nil {
		t.Fatalf("decode disconnect JSON: %v", err)
	}
	if payload.Text != "waking" {
		t.Errorf("disconnect text = %q, want %q", payload.Text, "waking")
	}
}
