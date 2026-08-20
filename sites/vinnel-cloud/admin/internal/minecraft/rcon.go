// Source RCON client, as implemented by the Minecraft server: length-prefixed
// little-endian packets, an auth handshake, then one request/response per command.
package minecraft

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"time"
)

const (
	rconTypeResponse     = 0
	rconTypeCommand      = 2
	rconTypeAuthResponse = 2
	rconTypeAuth         = 3
)

type rconConn struct {
	c net.Conn
}

func rconDial(addr, password string) (*rconConn, error) {
	if addr == "" {
		return nil, errors.New("RCON address not configured")
	}
	if password == "" {
		return nil, errors.New("RCON password not configured")
	}
	c, err := net.DialTimeout("tcp", addr, minecraftDialTimeout)
	if err != nil {
		return nil, err
	}
	r := &rconConn{c: c}
	c.SetDeadline(time.Now().Add(minecraftDialTimeout))

	if err := r.send(1, rconTypeAuth, password); err != nil {
		c.Close()
		return nil, err
	}
	// Some implementations emit an empty RESPONSE_VALUE ahead of the auth
	// reply; skip anything that is not the auth response itself.
	for {
		id, typ, _, err := r.recv()
		if err != nil {
			c.Close()
			return nil, err
		}
		if typ != rconTypeAuthResponse {
			continue
		}
		if id == -1 {
			c.Close()
			return nil, errors.New("RCON authentication failed")
		}
		return r, nil
	}
}

func (r *rconConn) Close() error { return r.c.Close() }

func (r *rconConn) send(id, typ int32, body string) error {
	var buf bytes.Buffer
	binary.Write(&buf, binary.LittleEndian, int32(len(body)+10))
	binary.Write(&buf, binary.LittleEndian, id)
	binary.Write(&buf, binary.LittleEndian, typ)
	buf.WriteString(body)
	buf.Write([]byte{0, 0})
	_, err := r.c.Write(buf.Bytes())
	return err
}

func (r *rconConn) recv() (int32, int32, string, error) {
	var length int32
	if err := binary.Read(r.c, binary.LittleEndian, &length); err != nil {
		return 0, 0, "", err
	}
	if length < 10 || length > rconMaxPacket {
		return 0, 0, "", fmt.Errorf("rcon packet length %d out of range", length)
	}
	buf := make([]byte, length)
	if _, err := io.ReadFull(r.c, buf); err != nil {
		return 0, 0, "", err
	}
	id := int32(binary.LittleEndian.Uint32(buf[0:4]))
	typ := int32(binary.LittleEndian.Uint32(buf[4:8]))
	return id, typ, string(bytes.TrimRight(buf[8:], "\x00")), nil
}

// exec runs one command and returns its output. Responses longer than 4096
// bytes arrive as several packets with no end marker, so after the first one
// the read deadline drops to rconDrainWindow and a timeout means "done".
func (r *rconConn) exec(cmd string) (string, error) {
	r.c.SetDeadline(time.Now().Add(minecraftDialTimeout))
	if err := r.send(2, rconTypeCommand, cmd); err != nil {
		return "", err
	}
	_, _, first, err := r.recv()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(first)
	for {
		r.c.SetDeadline(time.Now().Add(rconDrainWindow))
		_, typ, body, err := r.recv()
		if err != nil {
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() {
				break
			}
			if errors.Is(err, io.EOF) {
				break
			}
			return sb.String(), err
		}
		if typ != rconTypeResponse {
			continue
		}
		sb.WriteString(body)
	}
	return stripFormatting(sb.String()), nil
}
