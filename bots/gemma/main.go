package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"gemma/internal/bot"
	"gemma/internal/llm"
	"gemma/internal/room"
	"gemma/internal/tools"
)

const (
	socksPort   = "127.0.0.1:9050"
	controlPort = "127.0.0.1:9051"
	torOrPorts  = "*:443"
	torWait     = 10 * time.Minute
	chatGrace   = 15 * time.Second
	torGrace    = 5 * time.Second
)

type process struct {
	cmd  *exec.Cmd
	done chan struct{}
	err  error
}

func start(cmd *exec.Cmd) (*process, error) {
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	p := &process{cmd: cmd, done: make(chan struct{})}
	go func() {
		p.err = cmd.Wait()
		close(p.done)
	}()
	return p, nil
}

func (p *process) stop(grace time.Duration) {
	select {
	case <-p.done:
		return
	default:
	}
	p.cmd.Process.Signal(syscall.SIGTERM)
	select {
	case <-p.done:
	case <-time.After(grace):
		p.cmd.Process.Kill()
		<-p.done
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	log.SetFlags(0)
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	if err := run(ctx); err != nil {
		log.Fatal(err)
	}
}

func run(ctx context.Context) error {
	var missing []string
	for _, key := range []string{"LLM_BASE_URL", "LLM_MODEL"} {
		if os.Getenv(key) == "" {
			missing = append(missing, key)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing %s", strings.Join(missing, ", "))
	}
	nick := env("CHAT_NICK", "Gemma")
	knowledge, err := os.ReadFile(env("KNOWLEDGE_FILE", "/etc/gemma/knowledge.md"))
	if err != nil {
		return err
	}

	var torDone <-chan struct{}
	viaTor := os.Getenv("TOR_PATH") != ""
	if viaTor {
		tor, ready, err := startTor(os.Getenv("TOR_PATH"), env("TOR_DATA", "/var/lib/tor/data"))
		if err != nil {
			return err
		}
		defer tor.stop(torGrace)
		torDone = tor.done
		select {
		case <-ready:
		case <-tor.done:
			return fmt.Errorf("tor exited before it connected: %v", tor.err)
		case <-time.After(torWait):
			return fmt.Errorf("tor didn't connect within %s", torWait)
		case <-ctx.Done():
			return nil
		}
	}

	box, err := toolbox(viaTor)
	if err != nil {
		return err
	}

	chat, stdin, events, err := startChat(ctx, nick, viaTor)
	if err != nil {
		return err
	}
	defer chat.stop(chatGrace)

	b := &bot.Bot{
		Nick:   nick,
		Prompt: bot.Prompt(nick, string(knowledge), box.Describe()),
		LLM: &llm.Client{
			BaseURL:     os.Getenv("LLM_BASE_URL"),
			Model:       os.Getenv("LLM_MODEL"),
			APIKey:      os.Getenv("LLM_API_KEY"),
			Temperature: 0.7,
		},
		Send: func(line string) error {
			_, err := io.WriteString(stdin, line+"\n")
			return err
		},
		Peers: func() error {
			_, err := io.WriteString(stdin, ":peers\n:timer\n")
			return err
		},
		Verify: func(name string) error {
			_, err := io.WriteString(stdin, ":verify "+name+"\n")
			return err
		},
		Tools: box,
		Owner: strings.ToLower(strings.ReplaceAll(os.Getenv("OWNER_FINGERPRINT"), " ", "")),
		Logf:  log.Printf,
	}
	botDone := make(chan error, 1)
	go func() { botDone <- b.Run(ctx, events) }()

	select {
	case <-ctx.Done():
		log.Print("leaving the room")
		stdin.Close()
		select {
		case <-chat.done:
		case <-time.After(chatGrace):
		}
		return nil
	case <-chat.done:
		return fmt.Errorf("chat exited: %v", chat.err)
	case <-torDone:
		return fmt.Errorf("tor exited")
	case err := <-botDone:
		return fmt.Errorf("the bot stopped: %v", err)
	}
}

func toolbox(viaTor bool) (*tools.Toolbox, error) {
	box := &tools.Toolbox{}
	on := []string{"time", "calculate", "notes"}
	if u := os.Getenv("SEARCH_URL"); u != "" {
		box.Search = &tools.Searcher{BaseURL: u, HTTP: &http.Client{Timeout: time.Minute}}
		on = append(on, "search")
	}
	if viaTor {
		box.Read = tools.TorReader(socksPort)
		on = append(on, "reading pages over Tor")
	}
	path := os.Getenv("NOTES_FILE")
	notes, err := tools.OpenNotebook(path, log.Printf)
	if err != nil {
		return nil, fmt.Errorf("opening the notebook: %w", err)
	}
	box.Notes = notes
	where := "in memory only"
	if path != "" {
		where = path
	}
	log.Printf("tools: %s; %d notes, kept %s", strings.Join(on, ", "), len(notes.Notes()), where)
	return box, nil
}

func startTor(path, data string) (*process, <-chan struct{}, error) {
	cmd := exec.Command(path,
		"--defaults-torrc", "/nonexistent", "-f", "/nonexistent", "--ignore-missing-torrc",
		"--SocksPort", socksPort,
		"--ControlPort", controlPort,
		"--CookieAuthentication", "1",
		"--DataDirectory", data,
		"--ReachableAddresses", torOrPorts,
		"--ClientUseIPv6", "0",
		"--AvoidDiskWrites", "1",
		"--Log", "notice stdout",
	)
	cmd.Env = []string{"HOME=" + data}
	cmd.Stderr = os.Stderr
	out, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, err
	}
	tor, err := start(cmd)
	if err != nil {
		return nil, nil, fmt.Errorf("starting tor: %w", err)
	}
	ready := make(chan struct{})
	go func() {
		connected := false
		sc := bufio.NewScanner(out)
		for sc.Scan() {
			line := sc.Text()
			if i := strings.Index(line, "] "); i >= 0 {
				line = line[i+2:]
			}
			log.Printf("tor: %s", line)
			if !connected && strings.HasPrefix(line, "Bootstrapped 100%") {
				connected = true
				close(ready)
			}
		}
	}()
	return tor, ready, nil
}

func startChat(ctx context.Context, nick string, viaTor bool) (*process, io.WriteCloser, <-chan room.Event, error) {
	home := env("CHAT_HOME", "/home/gemma")
	args := []string{"--simple", "--session", env("CHAT_SESSION", "vin-moe-party"), "--nick", nick, "--verify-optional"}
	if colour := os.Getenv("CHAT_COLOUR"); colour != "" {
		args = append(args, "--colour", colour)
	}
	chatEnv := []string{
		"HOME=" + home,
		"XDG_CONFIG_HOME=" + home + "/.config",
		"TMPDIR=" + env("TMPDIR", "/tmp"),
		"PATH=/usr/local/bin:/usr/bin:/bin",
		"LANG=C.UTF-8",
		"NO_COLOR=1",
		"CHAT_PASSWORD=" + os.Getenv("CHAT_PASSWORD"),
	}
	if password := os.Getenv("CHAT_SIGN_PASSWORD"); password != "" {
		args = append(args, "--identity", "age")
		chatEnv = append(chatEnv, "CHAT_SIGN_PASSWORD="+password)
	}
	if viaTor {
		args = append(args, "--routing", "tor", "--tor-launch", "never",
			"--tor-socks", socksPort, "--tor-control", controlPort, "--nostr", "always")
	}
	args = append(args, strings.Fields(os.Getenv("CHAT_ARGS"))...)

	cmd := exec.Command(env("CHAT_PATH", "chat"), args...)
	cmd.Env = chatEnv
	cmd.Dir = home
	cmd.Stderr = os.Stderr
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, nil, nil, err
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, nil, err
	}
	chat, err := start(cmd)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("starting chat: %w", err)
	}
	events := make(chan room.Event, 64)
	go func() {
		defer close(events)
		joined := false
		sc := bufio.NewScanner(out)
		sc.Buffer(make([]byte, 64<<10), 1<<20)
		for sc.Scan() {
			ev := room.Parse(sc.Text())
			if !joined {
				joined = ev.Kind == room.Banner
				log.Printf("chat: %s", sc.Text())
				continue
			}
			switch ev.Kind {
			case room.Banner, room.Console, room.Other:
				log.Printf("chat: %s", ev.Text)
			case room.Join, room.Leave:
				log.Printf("chat: %d online", ev.Online)
			}
			select {
			case events <- ev:
			case <-ctx.Done():
			}
		}
	}()
	return chat, stdin, events, nil
}
