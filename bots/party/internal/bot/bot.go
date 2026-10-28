package bot

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"party/internal/llm"
	"party/internal/room"
)

type Asker interface {
	Ask(ctx context.Context, messages []llm.Message, schema json.RawMessage, maxTokens int) (string, error)
}

const (
	maxTurns       = 40
	maxBytes       = 12000
	maxDirect      = 64
	maxQueued      = 16
	maxSenders     = 512
	maxListed      = 40
	maxAddressed   = 8
	replyChars     = 600
	replyTokens    = 200
	directTokens   = 256
	burst          = 4
	refill         = 15 * time.Second
	greetEvery     = 30 * time.Minute
	staleAfter     = 3 * time.Minute
	spacing        = 2 * time.Second
	peersWait      = 5 * time.Second
	firstBackoff   = 5 * time.Second
	maxBackoff     = 2 * time.Minute
	defaultTimeout = 2 * time.Minute
)

type Bot struct {
	Nick    string
	Prompt  string
	LLM     Asker
	Send    func(line string) error
	Peers   func() error
	Logf    func(format string, args ...any)
	Now     func() time.Time
	Timeout time.Duration

	room      conversation
	direct    map[string]*conversation
	queue     []*conversation
	senders   map[string]*bucket
	greeted   map[string]time.Time
	online    map[string]int
	roster    map[string]int
	waiting   *conversation
	waitUntil time.Time
	listed    bool
	busy      bool
	readyAt   time.Time
	failures  int
}

type bucket struct {
	tokens float64
	at     time.Time
}

type result struct {
	conv  *conversation
	after uint64
	to    []string
	reply string
	err   error
	took  time.Duration
}

func (b *Bot) Run(ctx context.Context, events <-chan room.Event) error {
	results := make(chan result, 1)
	for {
		var wake <-chan time.Time
		if wait := b.next(ctx, results); wait > 0 {
			wake = time.After(wait)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case ev, ok := <-events:
			if !ok {
				return nil
			}
			b.Handle(ev)
		case r := <-results:
			b.finish(r)
		case <-wake:
		}
	}
}

func (b *Bot) Handle(ev room.Event) {
	b.init()
	if b.roster != nil && ev.Kind != room.PeersEntry {
		b.listedNow()
	}
	now := b.now()
	switch ev.Kind {
	case room.Message:
		b.heard(&b.room, ev.Nick, ev.Nick+": "+ev.Text, now)
	case room.Direct:
		b.heard(b.dm(ev.Sender), ev.Nick, ev.Nick+": "+ev.Text, now)
	case room.Join:
		b.online[ev.Nick]++
		if b.online[ev.Nick] > 1 {
			return
		}
		greet := b.greets(ev.Nick, now)
		b.room.add(turn{role: "user", text: "[" + ev.Nick + " joined]", nick: ev.Nick, join: true, trigger: greet}, 0)
		if greet {
			b.room.heard = now
			b.mark(&b.room)
		}
	case room.Leave:
		if n := b.online[ev.Nick]; n > 1 {
			b.online[ev.Nick] = n - 1
		} else if n == 1 {
			b.gone(ev.Nick)
		}
		if ev.Online <= 1 {
			for nick := range b.online {
				b.gone(nick)
			}
		}
	case room.PeersHead:
		if b.waiting != nil && !b.listed {
			b.roster = map[string]int{}
		}
	case room.PeersEntry:
		if b.roster != nil {
			b.roster[ev.Nick]++
		}
	case room.PeersNone:
		if b.waiting != nil && !b.listed {
			b.roster = map[string]int{}
			b.listedNow()
		}
	}
}

func (b *Bot) init() {
	if b.direct == nil {
		b.direct = map[string]*conversation{}
		b.senders = map[string]*bucket{}
		b.greeted = map[string]time.Time{}
		b.online = map[string]int{}
	}
}

func (b *Bot) now() time.Time {
	if b.Now != nil {
		return b.Now()
	}
	return time.Now()
}

func (b *Bot) logf(format string, args ...any) {
	if b.Logf != nil {
		b.Logf(format, args...)
	}
}

func (b *Bot) gone(nick string) {
	delete(b.online, nick)
	b.room.add(turn{role: "user", text: "[" + nick + " left]", nick: nick}, 0)
}

func (b *Bot) listedNow() {
	for nick := range b.online {
		if b.roster[nick] == 0 {
			b.gone(nick)
		}
	}
	b.online = b.roster
	b.roster = nil
	b.listed = true
}

func (b *Bot) greets(nick string, now time.Time) bool {
	if last, ok := b.greeted[nick]; ok && now.Sub(last) < greetEvery {
		return false
	}
	if len(b.greeted) >= maxSenders {
		for name, at := range b.greeted {
			if now.Sub(at) >= greetEvery {
				delete(b.greeted, name)
			}
		}
	}
	b.greeted[nick] = now
	return true
}

func (b *Bot) heard(c *conversation, nick, text string, now time.Time) {
	trigger := b.allow(nick, now)
	c.add(turn{role: "user", text: text, nick: nick, trigger: trigger}, 0)
	c.heard = now
	if trigger {
		b.mark(c)
	}
}

func (b *Bot) mark(c *conversation) {
	c.pending = true
	if c.queued || (c.peer != "" && len(b.queue) >= maxQueued) {
		return
	}
	c.queued = true
	b.queue = append(b.queue, c)
}

func (b *Bot) dm(peer string) *conversation {
	if c, ok := b.direct[peer]; ok {
		return c
	}
	if len(b.direct) >= maxDirect {
		var oldest *conversation
		for _, c := range b.direct {
			if oldest == nil || c.heard.Before(oldest.heard) {
				oldest = c
			}
		}
		delete(b.direct, oldest.peer)
	}
	c := &conversation{peer: peer}
	b.direct[peer] = c
	return c
}

func (b *Bot) allow(sender string, now time.Time) bool {
	k := b.senders[sender]
	if k == nil {
		if len(b.senders) >= maxSenders {
			for name, old := range b.senders {
				if now.Sub(old.at) >= burst*refill {
					delete(b.senders, name)
				}
			}
			if len(b.senders) >= maxSenders {
				return false
			}
		}
		k = &bucket{tokens: burst, at: now}
		b.senders[sender] = k
	}
	k.tokens = min(burst, k.tokens+now.Sub(k.at).Seconds()/refill.Seconds())
	k.at = now
	if k.tokens < 1 {
		return false
	}
	k.tokens--
	return true
}

func (b *Bot) next(ctx context.Context, results chan<- result) time.Duration {
	for !b.busy {
		now := b.now()
		if c := b.waiting; c != nil {
			if wait := b.waitUntil.Sub(now); !b.listed && wait > 0 {
				return wait
			}
			if !b.listed {
				b.roster = nil
				b.logf("chat didn't list its peers within %s; going by joins and leaves", peersWait)
			}
			b.waiting = nil
			b.start(ctx, c, results)
			continue
		}
		if len(b.queue) == 0 {
			return 0
		}
		if wait := b.readyAt.Sub(now); wait > 0 {
			return wait
		}
		c := b.queue[0]
		b.queue = b.queue[1:]
		c.queued = false
		if !c.pending {
			continue
		}
		c.pending = false
		if now.Sub(c.heard) > staleAfter {
			b.logf("skipped a reply to %s: its messages waited too long", c.where())
			continue
		}
		if c.peer == "" && b.Peers != nil {
			err := b.Peers()
			if err == nil {
				b.waiting, b.waitUntil, b.listed = c, now.Add(peersWait), false
				continue
			}
			b.logf("couldn't ask chat who is here: %v", err)
		}
		b.start(ctx, c, results)
	}
	return 0
}

func (b *Bot) start(ctx context.Context, c *conversation, results chan<- result) {
	system := b.system(c)
	var to []string
	var schema json.RawMessage
	tokens := directTokens
	if c.peer == "" {
		if to = b.addressees(c); len(to) == 0 {
			return
		}
		schema = replySchema(to)
		tokens = 64 + replyTokens*len(to)
		system += "\n\nReply now to " + strings.Join(to, ", ") + ": one reply each, in the field named after them. " +
			"Each reply answers everything that person said since your last reply, as a whole, and greets them if they just joined. " +
			"Don't start a reply with their @nick; it's added for you."
	}
	msgs, after := c.messages(system)
	if msgs[len(msgs)-1].Role != "user" {
		return
	}
	timeout := b.Timeout
	if timeout <= 0 {
		timeout = defaultTimeout
	}
	b.busy = true
	go func() {
		ctx, cancel := context.WithTimeout(ctx, timeout)
		defer cancel()
		start := time.Now()
		reply, err := b.LLM.Ask(ctx, msgs, schema, tokens)
		results <- result{conv: c, after: after, to: to, reply: reply, err: err, took: time.Since(start)}
	}()
}

func (b *Bot) addressees(c *conversation) []string {
	from := len(c.turns)
	for from > 0 && c.turns[from-1].role != "assistant" {
		from--
	}
	var to []string
	seen := map[string]bool{}
	for _, t := range c.turns[from:] {
		if !t.trigger || seen[t.nick] || (t.join && b.online[t.nick] == 0) {
			continue
		}
		seen[t.nick] = true
		to = append(to, t.nick)
	}
	if len(to) > maxAddressed {
		b.logf("%d people to answer at once; answering the first %d", len(to), maxAddressed)
		to = to[:maxAddressed]
	}
	return to
}

func replySchema(to []string) json.RawMessage {
	var s strings.Builder
	s.WriteString(`{"type":"object","properties":{`)
	for i, nick := range to {
		if i > 0 {
			s.WriteByte(',')
		}
		key, _ := json.Marshal(nick)
		s.Write(key)
		fmt.Fprintf(&s, `:{"type":"string","minLength":1,"maxLength":%d}`, replyChars)
	}
	required, _ := json.Marshal(to)
	s.WriteString(`},"required":`)
	s.Write(required)
	s.WriteString(`,"additionalProperties":false}`)
	return json.RawMessage(s.String())
}

func (b *Bot) finish(r result) {
	b.busy = false
	now := b.now()
	var replies map[string]string
	if r.err == nil && r.conv.peer == "" {
		if err := json.Unmarshal([]byte(r.reply), &replies); err != nil {
			r.err = fmt.Errorf("the replies weren't the JSON asked for: %w", err)
		}
	}
	if r.err != nil {
		b.failures++
		wait := min(firstBackoff<<min(b.failures-1, 5), maxBackoff)
		b.readyAt = now.Add(wait)
		b.logf("no reply to %s: %v; next try in %s", r.conv.where(), r.err, wait)
		b.mark(r.conv)
		return
	}
	b.failures = 0
	b.readyAt = now.Add(spacing)

	var lines, shown []string
	if r.conv.peer != "" {
		prefix := ":msg " + r.conv.peer + " "
		if text := room.Clean(trimSelf(r.reply, b.Nick), room.MaxLine-len(prefix)); text != "" {
			lines, shown = append(lines, prefix+text), append(shown, text)
		}
	} else {
		for _, nick := range r.to {
			prefix := "@" + nick + " "
			if text := room.Clean(trimTo(trimSelf(replies[nick], b.Nick), nick), room.MaxLine-len(prefix)); text != "" {
				lines, shown = append(lines, prefix+text), append(shown, prefix+text)
			}
		}
	}
	if len(lines) == 0 {
		b.logf("the reply to %s was empty once cleaned", r.conv.where())
		return
	}
	sent := 0
	for _, line := range lines {
		if err := b.Send(line); err != nil {
			b.logf("couldn't hand a reply to chat: %v", err)
			break
		}
		sent++
	}
	if sent == 0 {
		return
	}
	r.conv.add(turn{role: "assistant", text: strings.Join(shown[:sent], "\n")}, r.after)
	if r.conv.peer != "" {
		b.logf("replied to a direct message in %s", r.took.Round(100*time.Millisecond))
	} else {
		b.logf("replied to %d in the room in %s", sent, r.took.Round(100*time.Millisecond))
	}
}

func (b *Bot) system(c *conversation) string {
	if c.peer != "" {
		return b.Prompt + "\n\nThis conversation is a direct message from " + c.peer + ": only the two of you see it."
	}
	if len(b.online) == 0 {
		return b.Prompt + "\n\nNobody else is in the room right now."
	}
	names := make([]string, 0, len(b.online))
	for nick := range b.online {
		names = append(names, nick)
	}
	sort.Strings(names)
	if len(names) > maxListed {
		names = append(names[:maxListed], fmt.Sprintf("and %d more", len(names)-maxListed))
	}
	return b.Prompt + "\n\nIn the room right now, besides you: " + strings.Join(names, ", ") + "."
}

func trimSelf(reply, nick string) string {
	s := strings.TrimSpace(reply)
	for _, p := range []string{nick + " (you):", nick + ":"} {
		if len(s) >= len(p) && strings.EqualFold(s[:len(p)], p) {
			s = s[len(p):]
		}
	}
	return s
}

func trimTo(reply, nick string) string {
	s := strings.TrimSpace(reply)
	for _, p := range []string{"@" + nick, nick + ":", nick + ","} {
		if len(s) < len(p) || !strings.EqualFold(s[:len(p)], p) {
			continue
		}
		if r, _ := utf8.DecodeRuneInString(s[len(p):]); unicode.IsLetter(r) || unicode.IsDigit(r) {
			continue
		}
		return strings.TrimLeft(s[len(p):], " ,:!-")
	}
	return s
}

type turn struct {
	seq     uint64
	role    string
	text    string
	nick    string
	join    bool
	trigger bool
}

type conversation struct {
	peer    string
	turns   []turn
	size    int
	seq     uint64
	pending bool
	queued  bool
	heard   time.Time
}

func (c *conversation) where() string {
	if c.peer == "" {
		return "the room"
	}
	return "a direct message"
}

func (c *conversation) add(t turn, after uint64) {
	c.seq++
	t.seq = c.seq
	at := len(c.turns)
	if after != 0 {
		at = 0
		for i, old := range c.turns {
			if old.seq == after {
				at = i + 1
				break
			}
		}
	}
	c.turns = append(c.turns, turn{})
	copy(c.turns[at+1:], c.turns[at:])
	c.turns[at] = t
	c.size += len(t.text)
	for len(c.turns) > maxTurns || (c.size > maxBytes && len(c.turns) > 1) {
		c.size -= len(c.turns[0].text)
		c.turns = c.turns[1:]
	}
}

func (c *conversation) messages(system string) ([]llm.Message, uint64) {
	msgs := []llm.Message{{Role: "system", Content: system}}
	var last uint64
	for _, t := range c.turns {
		if len(msgs) == 1 && t.role != "user" {
			continue
		}
		if prev := &msgs[len(msgs)-1]; len(msgs) > 1 && prev.Role == t.role {
			prev.Content += "\n" + t.text
		} else {
			msgs = append(msgs, llm.Message{Role: t.role, Content: t.text})
		}
		last = t.seq
	}
	return msgs, last
}
