package minecraft

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"strings"
	"testing"
)

func writeRconPacket(w io.Writer, id, typ int32, body string) {
	var buf bytes.Buffer
	binary.Write(&buf, binary.LittleEndian, int32(len(body)+10))
	binary.Write(&buf, binary.LittleEndian, id)
	binary.Write(&buf, binary.LittleEndian, typ)
	buf.WriteString(body)
	buf.Write([]byte{0, 0})
	w.Write(buf.Bytes())
}

// readRconPacket returns an error rather than failing the test: it runs on the
// fake server's goroutine, where a clean client disconnect is an expected EOF.
func readRconPacket(r io.Reader) (int32, int32, string, error) {
	var length int32
	if err := binary.Read(r, binary.LittleEndian, &length); err != nil {
		return 0, 0, "", err
	}
	buf := make([]byte, length)
	if _, err := io.ReadFull(r, buf); err != nil {
		return 0, 0, "", err
	}
	id := int32(binary.LittleEndian.Uint32(buf[0:4]))
	typ := int32(binary.LittleEndian.Uint32(buf[4:8]))
	return id, typ, string(bytes.TrimRight(buf[8:], "\x00")), nil
}

// fakeRconServer accepts one connection, authenticates against wantPassword,
// then replies to each command with the chunks the responder returns.
func fakeRconServer(t *testing.T, wantPassword string, responder func(cmd string) []string) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { ln.Close() })

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				id, typ, body, err := readRconPacket(conn)
				if err != nil || typ != rconTypeAuth {
					return
				}
				if body != wantPassword {
					writeRconPacket(conn, -1, rconTypeAuthResponse, "")
					return
				}
				writeRconPacket(conn, id, rconTypeAuthResponse, "")
				for {
					cid, ctyp, cmd, err := readRconPacket(conn)
					if err != nil || ctyp != rconTypeCommand {
						return
					}
					for _, chunk := range responder(cmd) {
						writeRconPacket(conn, cid, rconTypeResponse, chunk)
					}
				}
			}()
		}
	}()
	return ln.Addr().String()
}

func TestRconExec(t *testing.T) {
	addr := fakeRconServer(t, "s3cret", func(cmd string) []string {
		return []string{"There are 2 of a max of 20 players online: ida, vinnell"}
	})
	m := &Service{RconAddr: addr, RconPassword: "s3cret"}

	out, err := m.Command("list")
	if err != nil {
		t.Fatalf("command: %v", err)
	}
	if !strings.Contains(out, "2 of a max of 20") {
		t.Errorf("output = %q", out)
	}
}

func TestRconExecMultiPacket(t *testing.T) {
	addr := fakeRconServer(t, "pw", func(cmd string) []string {
		return []string{strings.Repeat("a", 4096), "tail"}
	})
	m := &Service{RconAddr: addr, RconPassword: "pw"}

	out, err := m.Command("help")
	if err != nil {
		t.Fatalf("command: %v", err)
	}
	if len(out) != 4096+len("tail") {
		t.Errorf("multi-packet output length = %d, want %d", len(out), 4096+len("tail"))
	}
}

func TestRconStripsLeadingSlashAndFormatting(t *testing.T) {
	var seen string
	addr := fakeRconServer(t, "pw", func(cmd string) []string {
		seen = cmd
		return []string{"§eSeed: §a[42]"}
	})
	m := &Service{RconAddr: addr, RconPassword: "pw"}

	out, err := m.Command("/seed")
	if err != nil {
		t.Fatalf("command: %v", err)
	}
	if seen != "seed" {
		t.Errorf("server saw %q, want %q", seen, "seed")
	}
	if out != "Seed: [42]" {
		t.Errorf("output = %q", out)
	}
}

func TestRconWrongPassword(t *testing.T) {
	addr := fakeRconServer(t, "right", func(cmd string) []string { return []string{"never"} })
	m := &Service{RconAddr: addr, RconPassword: "wrong"}

	if _, err := m.Command("list"); err == nil {
		t.Fatal("want auth error, got nil")
	}
}
