package main

import (
	"bufio"
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
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
	botGrace    = 5 * time.Second
	updateEvery = 24 * time.Hour
	updateRetry = time.Hour
	updateWait  = 3 * time.Minute
	torFold     = 10 * time.Minute
)

var torRepeats = []struct{ start, has, what string }{
	{"We tried for ", " using exit ", "streams retried on a new circuit"},
	{"Closed ", " streams for service ", "onion lookups failed"},
	{"Tried for ", ". Giving up.", "connections given up"},
}

type repeats struct {
	mu     sync.Mutex
	counts []int
}

func (r *repeats) fold(line string) bool {
	for i, rep := range torRepeats {
		if strings.HasPrefix(line, rep.start) && strings.Contains(line, rep.has) {
			r.mu.Lock()
			r.counts[i]++
			r.mu.Unlock()
			return true
		}
	}
	return false
}

func (r *repeats) flush() {
	r.mu.Lock()
	defer r.mu.Unlock()
	var parts []string
	for i, n := range r.counts {
		if n > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", n, torRepeats[i].what))
			r.counts[i] = 0
		}
	}
	if len(parts) > 0 {
		log.Printf("tor: repeated notices: %s", strings.Join(parts, ", "))
	}
}

type input struct {
	mu sync.Mutex
	w  io.WriteCloser
}

func (in *input) write(s string) error {
	in.mu.Lock()
	defer in.mu.Unlock()
	if in.w == nil {
		return errors.New("chat is restarting")
	}
	_, err := io.WriteString(in.w, s)
	return err
}

func (in *input) use(w io.WriteCloser) {
	in.mu.Lock()
	defer in.mu.Unlock()
	if in.w != nil {
		in.w.Close()
	}
	in.w = w
}

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
	kept, err := history()
	if err != nil {
		return err
	}
	chatPath, err := chatBinary()
	if err != nil {
		return err
	}
	updates := viaTor && os.Getenv("CHAT_UPDATE_DIR") != ""
	firstUpdate := updateEvery
	if !updates {
		log.Print("chat update: off (needs Tor and CHAT_UPDATE_DIR)")
	} else if _, err := updateChat(ctx, chatPath); err != nil {
		log.Printf("couldn't update chat: %v", err)
		firstUpdate = updateRetry
	}
	go loadDocs(ctx, box.Docs, chatPath)

	events := make(chan room.Event, 64)
	in := &input{}
	b := &bot.Bot{
		Nick:   nick,
		Prompt: bot.Prompt(nick, string(knowledge), box.Describe()),
		LLM: &llm.Client{
			BaseURL:     os.Getenv("LLM_BASE_URL"),
			Model:       os.Getenv("LLM_MODEL"),
			APIKey:      os.Getenv("LLM_API_KEY"),
			Temperature: 0.7,
		},
		Judge: &llm.Client{
			BaseURL: os.Getenv("LLM_BASE_URL"),
			Model:   os.Getenv("LLM_MODEL"),
			APIKey:  os.Getenv("LLM_API_KEY"),
		},
		Send: func(line string) error {
			return in.write(line + "\n")
		},
		Peers: func() error {
			return in.write(":peers\n:timer\n")
		},
		Verify: func(name string) error {
			return in.write(":verify " + name + "\n")
		},
		Tools:   box,
		History: kept,
		Owner:   strings.ToLower(strings.ReplaceAll(os.Getenv("OWNER_FINGERPRINT"), " ", "")),
		Logf:    log.Printf,
	}
	botDone := make(chan error, 1)
	go func() { botDone <- b.Run(ctx, events) }()

	var installed <-chan struct{}
	if updates {
		installed = updateDaily(ctx, chatPath, firstUpdate)
	}
	var chat *process
	defer func() {
		if chat != nil {
			chat.stop(chatGrace)
		}
	}()
	for {
		var stdin io.WriteCloser
		chat, stdin, err = startChat(ctx, chatPath, nick, viaTor, events)
		if err != nil {
			return err
		}
		in.use(stdin)
		select {
		case <-ctx.Done():
			log.Print("leaving the room")
			in.use(nil)
			select {
			case <-chat.done:
			case <-time.After(chatGrace):
			}
			select {
			case <-botDone:
			case <-time.After(botGrace):
			}
			return nil
		case <-chat.done:
			return fmt.Errorf("chat exited: %v", chat.err)
		case <-torDone:
			return fmt.Errorf("tor exited")
		case err := <-botDone:
			return fmt.Errorf("the bot stopped: %v", err)
		case <-installed:
			go loadDocs(ctx, box.Docs, chatPath)
			log.Print("rejoining the room with the new chat")
			in.use(nil)
			select {
			case <-chat.done:
			case <-time.After(chatGrace):
			}
			chat.stop(chatGrace)
		}
	}
}

var releaseVersion = regexp.MustCompile(`^chat (\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\b`)

func loadDocs(ctx context.Context, docs *tools.Docs, chatPath string) {
	if docs == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, updateWait)
	defer cancel()
	version, err := chatVersion(ctx, chatPath)
	m := releaseVersion.FindStringSubmatch(version)
	if err != nil || m == nil {
		log.Printf("chat docs: couldn't tell which chat this is (%q, %v)", version, err)
		return
	}
	start := time.Now()
	n, err := docs.Load(ctx, "v"+m[1])
	if err != nil {
		log.Printf("chat docs: couldn't load v%s over Tor; trying again when she looks something up: %v", m[1], err)
		return
	}
	log.Printf("chat docs: %d sections of v%s in %s", n, m[1], time.Since(start).Round(100*time.Millisecond))
}

func history() (*bot.History, error) {
	path := os.Getenv("HISTORY_FILE")
	if path == "" {
		log.Print("history: not kept")
		return nil, nil
	}
	key, err := hex.DecodeString(os.Getenv("HISTORY_KEY"))
	if err != nil || len(key) != 32 {
		return nil, errors.New("HISTORY_FILE needs HISTORY_KEY, 64 hex digits")
	}
	h, err := bot.OpenHistory(path, key)
	if err != nil {
		return nil, err
	}
	log.Printf("history: the room's, sealed in %s", path)
	return h, nil
}

func chatBinary() (string, error) {
	path := env("CHAT_PATH", "chat")
	dir := os.Getenv("CHAT_UPDATE_DIR")
	if dir == "" {
		return path, nil
	}
	dst := filepath.Join(dir, "chat")
	if _, err := os.Stat(dst); err == nil {
		return dst, nil
	}
	src, err := exec.LookPath(path)
	if err != nil {
		return "", err
	}
	if err := copyExecutable(src, dst); err != nil {
		return "", fmt.Errorf("copying chat to %s: %w", dir, err)
	}
	return dst, nil
}

func copyExecutable(src, dst string) error {
	from, err := os.Open(src)
	if err != nil {
		return err
	}
	defer from.Close()
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".chat-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := io.Copy(tmp, from); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(0o755); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), dst)
}

func chatVersion(ctx context.Context, path string) (string, error) {
	out, err := exec.CommandContext(ctx, path, "--version").Output()
	return strings.TrimSpace(string(out)), err
}

func updateChat(ctx context.Context, path string) (bool, error) {
	ctx, cancel := context.WithTimeout(ctx, updateWait)
	defer cancel()
	before, err := chatVersion(ctx, path)
	if err != nil {
		return false, err
	}
	log.Printf("chat update: checking over Tor, running %s", before)
	home := env("CHAT_HOME", "/home/gemma")
	cmd := exec.CommandContext(ctx, path, "--update", "--routing", "tor", "--tor-launch", "never",
		"--tor-socks", socksPort, "--tor-control", controlPort)
	cmd.Env = chatEnv(home)
	cmd.Dir = home
	out, err := cmd.CombinedOutput()
	for line := range strings.SplitSeq(strings.TrimSpace(string(out)), "\n") {
		if line != "" {
			log.Printf("chat update: %s", line)
		}
	}
	if err != nil {
		return false, err
	}
	after, err := chatVersion(ctx, path)
	if err != nil {
		return false, err
	}
	if after != before {
		log.Printf("chat update: installed %s over %s", after, before)
	}
	return after != before, nil
}

func updateDaily(ctx context.Context, path string, wait time.Duration) <-chan struct{} {
	installed := make(chan struct{}, 1)
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case <-time.After(wait):
			}
			newer, err := updateChat(ctx, path)
			wait = updateEvery
			switch {
			case err != nil:
				log.Printf("couldn't update chat: %v", err)
				wait = updateRetry
			case newer:
				select {
				case installed <- struct{}{}:
				default:
				}
			}
		}
	}()
	return installed
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
		box.Docs = &tools.Docs{Reader: box.Read}
		on = append(on, "reading pages, chat's docs and manuals over Tor")
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
	noise := &repeats{counts: make([]int, len(torRepeats))}
	go func() {
		t := time.NewTicker(torFold)
		defer t.Stop()
		for {
			select {
			case <-t.C:
				noise.flush()
			case <-tor.done:
				noise.flush()
				return
			}
		}
	}()
	go func() {
		connected := false
		sc := bufio.NewScanner(out)
		for sc.Scan() {
			line := sc.Text()
			if i := strings.Index(line, "] "); i >= 0 {
				line = line[i+2:]
			}
			if noise.fold(line) {
				continue
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

func chatEnv(home string) []string {
	return []string{
		"HOME=" + home,
		"XDG_CONFIG_HOME=" + home + "/.config",
		"TMPDIR=" + env("TMPDIR", "/tmp"),
		"PATH=/usr/local/bin:/usr/bin:/bin",
		"LANG=C.UTF-8",
		"NO_COLOR=1",
	}
}

func startChat(ctx context.Context, path, nick string, viaTor bool, events chan<- room.Event) (*process, io.WriteCloser, error) {
	home := env("CHAT_HOME", "/home/gemma")
	args := []string{"--simple", "--session", env("CHAT_SESSION", "vin-moe-party"), "--nick", nick, "--verify-optional"}
	if colour := os.Getenv("CHAT_COLOUR"); colour != "" {
		args = append(args, "--colour", colour)
	}
	vars := append(chatEnv(home), "CHAT_PASSWORD="+os.Getenv("CHAT_PASSWORD"))
	if password := os.Getenv("CHAT_SIGN_PASSWORD"); password != "" {
		args = append(args, "--identity", "age-nonick")
		vars = append(vars, "CHAT_SIGN_PASSWORD="+password)
	}
	if viaTor {
		args = append(args, "--routing", "tor", "--tor-launch", "never",
			"--tor-socks", socksPort, "--tor-control", controlPort, "--nostr", "always")
	}
	args = append(args, strings.Fields(os.Getenv("CHAT_ARGS"))...)

	cmd := exec.Command(path, args...)
	cmd.Env = vars
	cmd.Dir = home
	cmd.Stderr = os.Stderr
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, nil, err
	}
	out, err := cmd.StdoutPipe()
	if err != nil {
		return nil, nil, err
	}
	chat, err := start(cmd)
	if err != nil {
		return nil, nil, fmt.Errorf("starting chat: %w", err)
	}
	go func() {
		joined := false
		sc := bufio.NewScanner(out)
		sc.Buffer(make([]byte, 64<<10), 1<<20)
		for sc.Scan() {
			ev := room.Parse(sc.Text())
			if !joined {
				log.Printf("chat: %s", sc.Text())
				if joined = ev.Kind == room.Banner; !joined {
					continue
				}
			} else {
				switch ev.Kind {
				case room.Banner, room.Console, room.Other:
					log.Printf("chat: %s", ev.Text)
				}
			}
			select {
			case events <- ev:
			case <-ctx.Done():
			}
		}
	}()
	return chat, stdin, nil
}
