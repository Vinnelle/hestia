// Minecraft Server List Ping: the unauthenticated status query the multiplayer
// server list makes, plus the VarInt/packet primitives its wire format needs.
package minecraft

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"time"
)

func writeVarInt(w *bytes.Buffer, v int32) {
	uv := uint32(v)
	for {
		b := byte(uv & 0x7f)
		uv >>= 7
		if uv != 0 {
			b |= 0x80
		}
		w.WriteByte(b)
		if uv == 0 {
			return
		}
	}
}

func readVarInt(r io.Reader) (int32, error) {
	var res uint32
	var b [1]byte
	for i := 0; i < 5; i++ {
		if _, err := io.ReadFull(r, b[:]); err != nil {
			return 0, err
		}
		res |= uint32(b[0]&0x7f) << (7 * i)
		if b[0]&0x80 == 0 {
			return int32(res), nil
		}
	}
	return 0, errors.New("varint longer than 5 bytes")
}

func writeMCString(w *bytes.Buffer, s string) {
	writeVarInt(w, int32(len(s)))
	w.WriteString(s)
}

func mcPacket(id int32, payload []byte) []byte {
	var body bytes.Buffer
	writeVarInt(&body, id)
	body.Write(payload)
	var out bytes.Buffer
	writeVarInt(&out, int32(body.Len()))
	out.Write(body.Bytes())
	return out.Bytes()
}

type Ping struct {
	Version       string   `json:"version"`
	Protocol      int      `json:"protocol"`
	PlayersOnline int      `json:"playersOnline"`
	PlayersMax    int      `json:"playersMax"`
	Players       []string `json:"players"`
	MOTD          string   `json:"motd"`
	LatencyMS     int64    `json:"latencyMs"`
}

// chatText flattens a Minecraft chat component into plain text. The MOTD is a
// bare string on some servers and a nested {text,extra:[...]} tree on others.
func chatText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return s
	}
	var node struct {
		Text  string            `json:"text"`
		Extra []json.RawMessage `json:"extra"`
	}
	if err := json.Unmarshal(raw, &node); err == nil {
		var sb strings.Builder
		sb.WriteString(node.Text)
		for _, e := range node.Extra {
			sb.WriteString(chatText(e))
		}
		return sb.String()
	}
	var list []json.RawMessage
	if err := json.Unmarshal(raw, &list); err == nil {
		var sb strings.Builder
		for _, e := range list {
			sb.WriteString(chatText(e))
		}
		return sb.String()
	}
	return ""
}

// stripFormatting removes the section-sign colour codes Minecraft embeds in
// MOTDs, which would otherwise render as literal "§a" in the browser.
func stripFormatting(s string) string {
	var sb strings.Builder
	runes := []rune(s)
	for i := 0; i < len(runes); i++ {
		if runes[i] == '§' {
			i++
			continue
		}
		sb.WriteRune(runes[i])
	}
	return sb.String()
}

// pingMinecraft performs a Server List Ping: handshake into status state, then
// a status request. This is the same read-only query the multiplayer server
// list makes, so it needs no credentials.
func pingMinecraft(host string, port int) (*Ping, error) {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(port)), minecraftDialTimeout)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(minecraftDialTimeout))

	var hs bytes.Buffer
	writeVarInt(&hs, -1)
	writeMCString(&hs, host)
	binary.Write(&hs, binary.BigEndian, uint16(port))
	writeVarInt(&hs, 1)

	if _, err := conn.Write(mcPacket(0x00, hs.Bytes())); err != nil {
		return nil, err
	}
	if _, err := conn.Write(mcPacket(0x00, nil)); err != nil {
		return nil, err
	}

	length, err := readVarInt(conn)
	if err != nil {
		return nil, err
	}
	if length <= 0 || length > 1<<20 {
		return nil, fmt.Errorf("status packet length %d out of range", length)
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(conn, body); err != nil {
		return nil, err
	}
	r := bytes.NewReader(body)
	id, err := readVarInt(r)
	if err != nil {
		return nil, err
	}
	if id != 0x00 {
		return nil, fmt.Errorf("unexpected status packet id %d", id)
	}
	jsonLen, err := readVarInt(r)
	if err != nil {
		return nil, err
	}
	if jsonLen < 0 || int(jsonLen) > r.Len() {
		return nil, fmt.Errorf("status JSON length %d out of range", jsonLen)
	}
	payload := make([]byte, jsonLen)
	if _, err := io.ReadFull(r, payload); err != nil {
		return nil, err
	}

	var raw struct {
		Version struct {
			Name     string `json:"name"`
			Protocol int    `json:"protocol"`
		} `json:"version"`
		Players struct {
			Max    int `json:"max"`
			Online int `json:"online"`
			Sample []struct {
				Name string `json:"name"`
			} `json:"sample"`
		} `json:"players"`
		Description json.RawMessage `json:"description"`
	}
	if err := json.Unmarshal(payload, &raw); err != nil {
		return nil, err
	}

	out := &Ping{
		Version:       raw.Version.Name,
		Protocol:      raw.Version.Protocol,
		PlayersOnline: raw.Players.Online,
		PlayersMax:    raw.Players.Max,
		MOTD:          stripFormatting(chatText(raw.Description)),
		LatencyMS:     time.Since(start).Milliseconds(),
	}
	for _, p := range raw.Players.Sample {
		out.Players = append(out.Players, p.Name)
	}
	return out, nil
}
