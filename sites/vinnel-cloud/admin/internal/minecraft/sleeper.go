package minecraft

import (
	"bytes"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"sync"
	"time"

	"vinnel-cloud-admin/internal/gamesleep"
)

const (
	sleeperStateStatus  = 1
	sleeperStateLogin   = 2
	sleeperConnTimeout  = 10 * time.Second
	sleeperMaxPacket    = 1 << 15
	sleeperDefaultPoll  = 30 * time.Second
	sleeperDefaultIdle  = 15 * time.Minute
	sleeperDefaultMOTD  = "Sleeping — join to wake the server"
	sleeperDefaultWake  = "Waking the server up. Reconnect in about 30 seconds."
	sleeperVersionLabel = "Sleeping"
)

type Sleeper struct {
	Service     *Service
	Addr        string
	IdleTimeout time.Duration
	Poll        time.Duration
	MOTD        string
	WakeText    string

	mu        sync.Mutex
	listener  net.Listener
	idleSince time.Time
}

func (s *Sleeper) Run(ctx context.Context) error {
	if s.Service == nil || s.Service.Kube == nil {
		return errors.New("minecraft sleeper: kubernetes API unavailable")
	}
	if s.Service.Host == "" {
		return errors.New("minecraft sleeper: MINECRAFT_HOST not configured")
	}
	if s.Addr == "" {
		s.Addr = fmt.Sprintf(":%d", s.Service.Port)
	}
	if s.Poll <= 0 {
		s.Poll = sleeperDefaultPoll
	}
	if s.IdleTimeout <= 0 {
		s.IdleTimeout = sleeperDefaultIdle
	}
	defer s.closeListener()

	ticker := time.NewTicker(s.Poll)
	defer ticker.Stop()
	for {
		s.tick()
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func (s *Sleeper) tick() {
	desired, err := s.Service.Kube.DeploymentDesired(minecraftNamespace, minecraftDeployment)
	if err != nil {
		log.Printf("minecraft sleeper: desired replicas: %v", err)
		return
	}
	if desired == 0 {
		s.idleSince = time.Time{}
		if err := s.openListener(); err != nil {
			log.Printf("minecraft sleeper: listen on %s: %v", s.Addr, err)
		}
		return
	}

	s.closeListener()
	ping, err := pingMinecraft(s.Service.Host, s.Service.Port)
	if err != nil {
		s.idleSince = time.Time{}
		return
	}
	stop, next := gamesleep.Decide(ping.PlayersOnline, s.idleSince, time.Now(), s.IdleTimeout)
	s.idleSince = next
	if !stop {
		return
	}
	if err := s.Service.Stop(); err != nil {
		log.Printf("minecraft sleeper: stop: %v", err)
		return
	}
	log.Printf("minecraft sleeper: scaled to 0 after %s with no players", s.IdleTimeout)
}

func (s *Sleeper) openListener() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.listener != nil {
		return nil
	}
	ln, err := net.Listen("tcp", s.Addr)
	if err != nil {
		return err
	}
	s.listener = ln
	log.Printf("minecraft sleeper: holding %s while the server is asleep", s.Addr)
	go s.serve(ln)
	return nil
}

func (s *Sleeper) closeListener() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.listener == nil {
		return
	}
	s.listener.Close()
	s.listener = nil
}

func (s *Sleeper) serve(ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go func() {
			defer conn.Close()
			if err := s.handle(conn); err != nil && !errors.Is(err, io.EOF) {
				log.Printf("minecraft sleeper: %v", err)
			}
		}()
	}
}

func (s *Sleeper) handle(conn net.Conn) error {
	conn.SetDeadline(time.Now().Add(sleeperConnTimeout))
	protocol, next, err := readSleeperHandshake(conn)
	if err != nil {
		return err
	}
	switch next {
	case sleeperStateStatus:
		return s.serveStatus(conn, protocol)
	case sleeperStateLogin:
		if err := writeLoginDisconnect(conn, s.wakeText()); err != nil {
			return err
		}
		s.wake()
		return nil
	default:
		return fmt.Errorf("handshake asked for state %d", next)
	}
}

func (s *Sleeper) serveStatus(conn net.Conn, protocol int32) error {
	for {
		id, body, err := readSleeperPacket(conn)
		if err != nil {
			return err
		}
		switch id {
		case 0x00:
			if err := writeStatusResponse(conn, protocol, s.motd()); err != nil {
				return err
			}
		case 0x01:
			_, err := conn.Write(mcPacket(0x01, body))
			return err
		default:
			return fmt.Errorf("status packet id %d", id)
		}
	}
}

func (s *Sleeper) wake() {
	s.closeListener()
	if err := s.Service.Start(); err != nil {
		log.Printf("minecraft sleeper: start: %v", err)
		if err := s.openListener(); err != nil {
			log.Printf("minecraft sleeper: relisten on %s: %v", s.Addr, err)
		}
		return
	}
	log.Print("minecraft sleeper: player knocked, scaled to 1")
}

func (s *Sleeper) motd() string {
	if s.MOTD == "" {
		return sleeperDefaultMOTD
	}
	return s.MOTD
}

func (s *Sleeper) wakeText() string {
	if s.WakeText == "" {
		return sleeperDefaultWake
	}
	return s.WakeText
}

func readSleeperPacket(r io.Reader) (int32, []byte, error) {
	length, err := readVarInt(r)
	if err != nil {
		return 0, nil, err
	}
	if length <= 0 || length > sleeperMaxPacket {
		return 0, nil, fmt.Errorf("packet length %d out of range", length)
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(r, body); err != nil {
		return 0, nil, err
	}
	buf := bytes.NewReader(body)
	id, err := readVarInt(buf)
	if err != nil {
		return 0, nil, err
	}
	rest := make([]byte, buf.Len())
	if _, err := io.ReadFull(buf, rest); err != nil {
		return 0, nil, err
	}
	return id, rest, nil
}

func readSleeperHandshake(r io.Reader) (int32, int32, error) {
	id, body, err := readSleeperPacket(r)
	if err != nil {
		return 0, 0, err
	}
	if id != 0x00 {
		return 0, 0, fmt.Errorf("handshake packet id %d", id)
	}
	buf := bytes.NewReader(body)
	protocol, err := readVarInt(buf)
	if err != nil {
		return 0, 0, err
	}
	hostLen, err := readVarInt(buf)
	if err != nil {
		return 0, 0, err
	}
	if hostLen < 0 || int(hostLen) > buf.Len() {
		return 0, 0, fmt.Errorf("handshake host length %d out of range", hostLen)
	}
	if _, err := io.CopyN(io.Discard, buf, int64(hostLen)); err != nil {
		return 0, 0, err
	}
	var port uint16
	if err := binary.Read(buf, binary.BigEndian, &port); err != nil {
		return 0, 0, err
	}
	next, err := readVarInt(buf)
	if err != nil {
		return 0, 0, err
	}
	return protocol, next, nil
}

func writeStatusResponse(w io.Writer, protocol int32, motd string) error {
	var payload struct {
		Version struct {
			Name     string `json:"name"`
			Protocol int32  `json:"protocol"`
		} `json:"version"`
		Players struct {
			Max    int `json:"max"`
			Online int `json:"online"`
		} `json:"players"`
		Description struct {
			Text string `json:"text"`
		} `json:"description"`
	}
	payload.Version.Name = sleeperVersionLabel
	payload.Version.Protocol = protocol
	payload.Description.Text = motd

	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	var out bytes.Buffer
	writeMCString(&out, string(body))
	_, err = w.Write(mcPacket(0x00, out.Bytes()))
	return err
}

func writeLoginDisconnect(w io.Writer, text string) error {
	body, err := json.Marshal(struct {
		Text string `json:"text"`
	}{Text: text})
	if err != nil {
		return err
	}
	var out bytes.Buffer
	writeMCString(&out, string(body))
	_, err = w.Write(mcPacket(0x00, out.Bytes()))
	return err
}
