package bot

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
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
	maxAsking      = 16
	replyChars     = 600
	replyTokens    = 200
	whyChars       = 160
	whyTokens      = 48
	directTokens   = 256
	burst          = 4
	refill         = 15 * time.Second
	greetEvery     = 30 * time.Minute
	staleAfter     = 3 * time.Minute
	spacing        = 2 * time.Second
	peersWait      = 5 * time.Second
	settle         = 3 * time.Second
	joinGrace      = 10 * time.Second
	maxHold        = 10 * time.Second
	alreadyHere    = 2 * time.Minute
	firstBackoff   = 5 * time.Second
	maxBackoff     = 30 * time.Second
	defaultTimeout = 2 * time.Minute
)

type Bot struct {
	Nick    string
	Prompt  string
	LLM     Asker
	Send    func(line string) error
	Peers   func() error
	Verify  func(name string) error
	Owner   string
	Logf    func(format string, args ...any)
	Now     func() time.Time
	Timeout time.Duration

	keys      map[string]string
	aliases   map[string]string
	counted   int
	asking    []string
	checking  *check
	started   time.Time
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

type check struct {
	name string
	key  string
}

type bucket struct {
	tokens float64
	at     time.Time
}

type result struct {
	conv   *conversation
	after  uint64
	to     []string
	joined map[string]bool
	reply  string
	err    error
	took   time.Duration
}

type roomReply struct {
	TalkingTo string `json:"talking_to"`
	Reply     string `json:"reply"`
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
	if b.checking != nil && ev.Kind != room.Fingerprint && ev.Kind != room.BadSignature && ev.Kind != room.VerifyEnd {
		b.checking = nil
	}
	now := b.now()
	switch ev.Kind {
	case room.Message:
		b.heard(&b.room, ev, now)
	case room.Direct:
		ev.Mention = false
		b.heard(b.dm(ev.Sender), ev, now)
	case room.Join:
		b.online[ev.Nick]++
		delete(b.keys, ev.Sender)
		delete(b.keys, ev.Nick)
		b.identify(ev.Sender)
		if b.online[ev.Nick] > 1 || now.Sub(b.started) < alreadyHere {
			return
		}
		greet := b.greets(ev.Nick, now)
		b.room.add(turn{role: "user", nick: ev.Nick, from: ev.Sender, join: true, trigger: greet}, 0)
		if greet && !b.room.pending {
			b.room.heard = now
			b.mark(&b.room, now.Add(joinGrace), now)
		}
	case room.Leave:
		delete(b.keys, ev.Sender)
		delete(b.keys, ev.Nick)
		if n := b.online[ev.Nick]; n > 1 {
			b.online[ev.Nick] = n - 1
		} else if n == 1 {
			b.gone(ev.Nick)
		}
		if ev.Online <= 1 {
			for nick := range b.online {
				b.gone(nick)
			}
			clear(b.keys)
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
	case room.VerifyCode:
		for i, name := range b.asking {
			if strings.EqualFold(bare(name), ev.Nick) {
				b.asking = b.asking[i+1:]
				b.checking = &check{name: ev.Sender, key: noKey}
				break
			}
		}
	case room.Fingerprint, room.BadSignature:
		if c := b.checking; c != nil && c.name == ev.Sender {
			c.key = b.alias(ev.Text, ev.Kind == room.Fingerprint)
		} else {
			b.checking = nil
		}
	case room.VerifyEnd:
		if c := b.checking; c != nil {
			if len(b.keys) >= maxSenders {
				b.keys = map[string]string{}
			}
			b.keys[c.name] = c.key
			b.checking = nil
		}
	case room.VerifyMiss:
		if len(b.asking) > 0 {
			b.asking = b.asking[1:]
		}
	}
}

func (b *Bot) aimedAt(ev room.Event) string {
	if strings.Contains(strings.ToLower(ev.Text), strings.ToLower(b.Nick)) {
		return ""
	}
	if rest, ok := strings.CutPrefix(ev.Text, "↪ "); ok {
		if nick, _, ok := strings.Cut(rest, ": "); ok && !strings.EqualFold(nick, ev.Nick) {
			return nick
		}
		return ""
	}
	target := ""
	lower := strings.ToLower(ev.Text)
	for nick := range b.online {
		if strings.EqualFold(nick, ev.Nick) || len(nick) <= len(target) {
			continue
		}
		for at := lower; ; {
			i := strings.Index(at, "@"+strings.ToLower(nick))
			if i < 0 {
				break
			}
			at = at[i+1+len(nick):]
			if r, _ := utf8.DecodeRuneInString(at); !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '-' && r != '_' {
				target = nick
				break
			}
		}
	}
	return target
}

func (b *Bot) identify(name string) {
	if b.Verify == nil || name == "" || len(name) > 64 || strings.IndexFunc(name, unicode.IsControl) >= 0 {
		return
	}
	if _, ok := b.keys[name]; ok || slices.Contains(b.asking, name) {
		return
	}
	nick, id, _ := strings.Cut(name, "#")
	if err := b.Verify(nick + "#" + id); err != nil {
		b.logf("couldn't ask chat for a signing key: %v", err)
		return
	}
	if len(b.asking) >= maxAsking {
		b.asking = b.asking[1:]
	}
	b.asking = append(b.asking, name)
}

func (b *Bot) alias(fp string, proven bool) string {
	switch {
	case !proven:
		return unprovenKey
	case b.Owner != "" && fp == b.Owner:
		return ownerKey
	}
	if a, ok := b.aliases[fp]; ok {
		return a
	}
	if len(b.aliases) >= maxSenders {
		b.aliases = map[string]string{}
	}
	b.counted++
	a := fmt.Sprintf("key %d", b.counted)
	b.aliases[fp] = a
	return a
}

func (b *Bot) keyOf(name, nick string) string {
	key := b.keys[name]
	if key != "" && key != ownerKey && b.Owner != "" && looksLikeOwner(nick) {
		key += ", not Finlay"
	}
	return key
}

func bare(name string) string {
	nick, _, _ := strings.Cut(name, "#")
	return nick
}

func (b *Bot) init() {
	if b.direct == nil {
		b.started = b.now()
		b.direct = map[string]*conversation{}
		b.senders = map[string]*bucket{}
		b.greeted = map[string]time.Time{}
		b.online = map[string]int{}
		b.keys = map[string]string{}
		b.aliases = map[string]string{}
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

func (b *Bot) heard(c *conversation, ev room.Event, now time.Time) {
	trigger := b.allow(ev.Nick, now)
	b.identify(ev.Sender)
	t := turn{role: "user", text: ev.Text, nick: ev.Nick, from: ev.Sender, key: b.keyOf(ev.Sender, ev.Nick), mention: ev.Mention, trigger: trigger}
	if c.peer == "" && !ev.Mention {
		t.target = b.aimedAt(ev)
	}
	c.add(t, 0)
	c.heard = now
	if trigger {
		b.mark(c, now.Add(settle), now)
	}
}

func (b *Bot) mark(c *conversation, due, now time.Time) {
	if !c.pending {
		c.first = now
	}
	c.due = due
	if limit := c.first.Add(maxHold); c.due.After(limit) {
		c.due = limit
	}
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
		i, wait := b.due(now)
		if i < 0 {
			return wait
		}
		c := b.queue[i]
		b.queue = append(b.queue[:i], b.queue[i+1:]...)
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

func (b *Bot) due(now time.Time) (int, time.Duration) {
	var wait time.Duration
	for i, c := range b.queue {
		left := c.due.Sub(now)
		if !c.pending || left <= 0 {
			return i, 0
		}
		if wait == 0 || left < wait {
			wait = left
		}
	}
	return -1, wait
}

func (b *Bot) start(ctx context.Context, c *conversation, results chan<- result) {
	for i := range c.turns {
		if t := &c.turns[i]; t.from != "" && t.key == "" {
			t.key = b.keyOf(t.from, t.nick)
		}
	}
	system := b.system(c)
	var to []string
	var joined map[string]bool
	var schema json.RawMessage
	tokens := directTokens
	if c.peer == "" {
		if to, joined = b.addressees(c); len(to) == 0 {
			return
		}
		schema = replySchema(to, joined)
		tokens = 64 + (whyTokens+replyTokens)*len(to)
		system += "\n\nSince your last turn, " + strings.Join(to, ", ") + " spoke or joined. Each has a field named after them, filled in order. " +
			"why: a few words on who they were talking to and how you can tell (who spoke just before them, whether they named or answered you or someone else, " +
			"whether they talk to you or about you). " +
			`talking_to: "you", "someone else" (another person, or about you rather than to you) or "everyone" (the room in general); ` +
			`it's "just joined" for someone who just joined. ` +
			`reply: your answer for "you", empty for "someone else", for "everyone" only when you can really help and nobody else has, ` +
			"and a greeting for someone who just joined, answering anything they said too. " +
			"A reply answers everything that person said since your last reply, as a whole. " +
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
		results <- result{conv: c, after: after, to: to, joined: joined, reply: reply, err: err, took: time.Since(start)}
	}()
}

func (b *Bot) addressees(c *conversation) ([]string, map[string]bool) {
	var to []string
	joined := map[string]bool{}
	open := map[string]bool{}
	for _, t := range c.turns {
		if t.seq <= c.done || !t.trigger || (t.join && b.online[t.nick] == 0) {
			continue
		}
		if _, seen := open[t.nick]; !seen {
			to = append(to, t.nick)
			open[t.nick] = false
		}
		if t.join {
			joined[t.nick] = true
		}
		if t.join || t.target == "" {
			open[t.nick] = true
		}
	}
	to = slices.DeleteFunc(to, func(nick string) bool { return !open[nick] })
	if len(to) > maxAddressed {
		b.logf("%d people to answer at once; answering the first %d", len(to), maxAddressed)
		to = to[:maxAddressed]
	}
	return to, joined
}

func replySchema(to []string, joined map[string]bool) json.RawMessage {
	branch := func(talkingTo string, minReply, maxReply int) string {
		return fmt.Sprintf(`{"type":"object","properties":{"why":{"type":"string","minLength":1,"maxLength":%d},"talking_to":{"const":%q},`+
			`"reply":{"type":"string","minLength":%d,"maxLength":%d}},"required":["why","talking_to","reply"],"additionalProperties":false}`,
			whyChars, talkingTo, minReply, maxReply)
	}
	var s strings.Builder
	s.WriteString(`{"type":"object","properties":{`)
	for i, nick := range to {
		if i > 0 {
			s.WriteByte(',')
		}
		key, _ := json.Marshal(nick)
		s.Write(key)
		s.WriteByte(':')
		if joined[nick] {
			s.WriteString(branch("just joined", 1, replyChars))
		} else {
			fmt.Fprintf(&s, `{"anyOf":[%s,%s,%s]}`, branch("you", 1, replyChars), branch("someone else", 0, 0), branch("everyone", 0, replyChars))
		}
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
	var replies map[string]roomReply
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
		b.mark(r.conv, now, now)
		return
	}
	b.failures = 0
	b.readyAt = now.Add(spacing)
	r.conv.done = r.after

	var lines, shown []string
	quiet := 0
	if r.conv.peer != "" {
		prefix := ":msg " + r.conv.peer + " "
		if text := room.Clean(trimSelf(r.reply, b.Nick), room.MaxLine-len(prefix)); text != "" {
			lines, shown = append(lines, prefix+text), append(shown, text)
		}
	} else {
		for _, nick := range r.to {
			reply := replies[nick]
			if strings.TrimSpace(reply.Reply) == "" || (reply.TalkingTo == "someone else" && !r.joined[nick]) {
				quiet++
				continue
			}
			prefix := "@" + nick + " "
			if text := room.Clean(trimTo(trimSelf(reply.Reply, b.Nick), nick), room.MaxLine-len(prefix)); text != "" {
				lines, shown = append(lines, prefix+text), append(shown, prefix+text)
			}
		}
	}
	if len(lines) == 0 {
		if quiet == len(r.to) && quiet > 0 {
			b.logf("stayed out of the room's conversation")
		} else {
			b.logf("the reply to %s was empty once cleaned", r.conv.where())
		}
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
		s := b.Prompt + "\n\nThis conversation is a direct message from " + c.peer + ": only the two of you see it."
		if b.Owner != "" {
			s += ownerTalking(b.keys[c.peer] == ownerKey)
		}
		return s
	}
	if len(b.online) == 0 {
		return b.Prompt + "\n\nNobody else is in the room right now."
	}
	names := make([]string, 0, len(b.online))
	owner := ""
	for nick := range b.online {
		key := b.keyOf(nick, nick)
		if key == ownerKey {
			owner = nick
		}
		if key != "" {
			nick += " [" + key + "]"
		}
		names = append(names, nick)
	}
	sort.Strings(names)
	if len(names) > maxListed {
		names = append(names[:maxListed], fmt.Sprintf("and %d more", len(names)-maxListed))
	}
	s := b.Prompt + "\n\nIn the room right now, besides you: " + strings.Join(names, ", ") + "."
	if b.Owner != "" {
		s += ownerHere(owner)
	}
	return s
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
	from    string
	key     string
	target  string
	mention bool
	join    bool
	trigger bool
}

func (t turn) line() string {
	if t.from == "" {
		return t.text
	}
	who := t.nick
	if t.key != "" {
		who += " [" + t.key + "]"
	}
	if t.join {
		return "[" + who + " joined]"
	}
	if t.mention {
		who += " (to you)"
	} else if t.target != "" {
		who += " (to " + t.target + ")"
	}
	return who + ": " + t.text
}

type conversation struct {
	peer    string
	turns   []turn
	size    int
	seq     uint64
	done    uint64
	pending bool
	queued  bool
	heard   time.Time
	first   time.Time
	due     time.Time
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
	c.size += len(t.text) + len(t.nick)
	for len(c.turns) > maxTurns || (c.size > maxBytes && len(c.turns) > 1) {
		c.size -= len(c.turns[0].text) + len(c.turns[0].nick)
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
			prev.Content += "\n" + t.line()
		} else {
			msgs = append(msgs, llm.Message{Role: t.role, Content: t.line()})
		}
		last = t.seq
	}
	return msgs, last
}
