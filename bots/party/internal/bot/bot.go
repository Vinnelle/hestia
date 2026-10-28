package bot

import (
	"context"
	"strings"
	"time"

	"party/internal/llm"
	"party/internal/room"
)

type Asker interface {
	Ask(ctx context.Context, messages []llm.Message) (string, error)
}

const (
	maxTurns       = 40
	maxBytes       = 12000
	maxDirect      = 64
	maxQueued      = 16
	maxSenders     = 512
	burst          = 4
	refill         = 15 * time.Second
	greetEvery     = 30 * time.Minute
	staleAfter     = 3 * time.Minute
	spacing        = 2 * time.Second
	firstBackoff   = 5 * time.Second
	maxBackoff     = 2 * time.Minute
	defaultTimeout = 2 * time.Minute
)

type Bot struct {
	Nick    string
	Prompt  string
	LLM     Asker
	Send    func(line string) error
	Logf    func(format string, args ...any)
	Now     func() time.Time
	Timeout time.Duration

	room     conversation
	direct   map[string]*conversation
	queue    []*conversation
	senders  map[string]*bucket
	greeted  map[string]time.Time
	busy     bool
	readyAt  time.Time
	failures int
}

type bucket struct {
	tokens float64
	at     time.Time
}

type result struct {
	conv  *conversation
	after uint64
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
	now := b.now()
	switch ev.Kind {
	case room.Message:
		b.heard(&b.room, ev.Sender, ev.Sender+": "+ev.Text, now)
	case room.Direct:
		b.heard(b.dm(ev.Sender), ev.Sender, ev.Sender+": "+ev.Text, now)
	case room.Join:
		b.room.add("user", "["+ev.Sender+" joined]", 0)
		if last, ok := b.greeted[ev.Sender]; ok && now.Sub(last) < greetEvery {
			return
		}
		if len(b.greeted) >= maxSenders {
			for name, at := range b.greeted {
				if now.Sub(at) >= greetEvery {
					delete(b.greeted, name)
				}
			}
		}
		b.greeted[ev.Sender] = now
		b.room.heard = now
		b.mark(&b.room)
	}
}

func (b *Bot) init() {
	if b.direct == nil {
		b.direct = map[string]*conversation{}
		b.senders = map[string]*bucket{}
		b.greeted = map[string]time.Time{}
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

func (b *Bot) heard(c *conversation, from, text string, now time.Time) {
	c.add("user", text, 0)
	c.heard = now
	if b.allow(from, now) {
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
	for !b.busy && len(b.queue) > 0 {
		now := b.now()
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
		msgs, after := c.messages(b.system(c))
		if msgs[len(msgs)-1].Role != "user" {
			continue
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
			reply, err := b.LLM.Ask(ctx, msgs)
			results <- result{conv: c, after: after, reply: reply, err: err, took: time.Since(start)}
		}()
	}
	return 0
}

func (b *Bot) finish(r result) {
	b.busy = false
	now := b.now()
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
	prefix := ""
	if r.conv.peer != "" {
		prefix = ":msg " + r.conv.peer + " "
	}
	text := room.Clean(trimSelf(r.reply, b.Nick), room.MaxLine-len(prefix))
	if text == "" {
		b.logf("the reply to %s was empty once cleaned", r.conv.where())
		return
	}
	if err := b.Send(prefix + text); err != nil {
		b.logf("couldn't hand the reply to chat: %v", err)
		return
	}
	r.conv.add("assistant", text, r.after)
	b.logf("replied to %s in %s", r.conv.where(), r.took.Round(100*time.Millisecond))
}

func (b *Bot) system(c *conversation) string {
	if c.peer == "" {
		return b.Prompt
	}
	return b.Prompt + "\n\nThis conversation is a direct message from " + c.peer + ": only the two of you see it."
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

type turn struct {
	seq  uint64
	role string
	text string
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

func (c *conversation) add(role, text string, after uint64) {
	c.seq++
	at := len(c.turns)
	if after != 0 {
		at = 0
		for i, t := range c.turns {
			if t.seq == after {
				at = i + 1
				break
			}
		}
	}
	c.turns = append(c.turns, turn{})
	copy(c.turns[at+1:], c.turns[at:])
	c.turns[at] = turn{seq: c.seq, role: role, text: text}
	c.size += len(text)
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
