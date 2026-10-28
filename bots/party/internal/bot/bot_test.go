package bot

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"party/internal/llm"
	"party/internal/room"
)

type fakeLLM struct {
	reply string
	err   error
	seen  [][]llm.Message
}

func (f *fakeLLM) Ask(ctx context.Context, messages []llm.Message) (string, error) {
	f.seen = append(f.seen, messages)
	return f.reply, f.err
}

type harness struct {
	bot     *Bot
	llm     *fakeLLM
	sent    []string
	now     time.Time
	results chan result
}

func newHarness(reply string) *harness {
	h := &harness{llm: &fakeLLM{reply: reply}, now: time.Date(2026, 10, 28, 12, 0, 0, 0, time.UTC), results: make(chan result, 1)}
	h.bot = &Bot{
		Nick:   "vin-bot",
		Prompt: Prompt("vin-bot", "Finlay wrote chat."),
		LLM:    h.llm,
		Send:   func(line string) error { h.sent = append(h.sent, line); return nil },
		Now:    func() time.Time { return h.now },
	}
	return h
}

func (h *harness) say(kind room.Kind, sender, text string) {
	h.bot.Handle(room.Event{Kind: kind, Sender: sender, Text: text})
}

func (h *harness) step() bool {
	h.bot.next(context.Background(), h.results)
	if !h.bot.busy {
		return false
	}
	h.bot.finish(<-h.results)
	h.now = h.now.Add(spacing)
	return true
}

func roles(msgs []llm.Message) string {
	var r []string
	for _, m := range msgs {
		r = append(r, m.Role)
	}
	return strings.Join(r, ",")
}

func TestRepliesToTheRoomInAlternatingTurns(t *testing.T) {
	h := newHarness("hi @alice and @bob")
	h.say(room.Message, "alice", "hello")
	h.say(room.Message, "bob", "hey bot")
	if !h.step() {
		t.Fatal("no reply")
	}
	if len(h.sent) != 1 || h.sent[0] != "hi @alice and @bob" {
		t.Fatalf("sent %q", h.sent)
	}
	msgs := h.llm.seen[0]
	if roles(msgs) != "system,user" || msgs[1].Content != "alice: hello\nbob: hey bot" {
		t.Errorf("messages = %+v", msgs)
	}

	h.say(room.Message, "alice", "and again")
	h.step()
	if got := roles(h.llm.seen[1]); got != "system,user,assistant,user" {
		t.Errorf("roles = %s", got)
	}
	if h.step() {
		t.Error("replied without anything new")
	}
}

func TestReplyGoesBeforeMessagesThatArrivedWhileThinking(t *testing.T) {
	h := newHarness("answer to one")
	h.say(room.Message, "alice", "one")
	h.bot.next(context.Background(), h.results)
	h.say(room.Message, "bob", "two")
	h.bot.finish(<-h.results)
	h.now = h.now.Add(spacing)
	h.step()
	msgs := h.llm.seen[1]
	if roles(msgs) != "system,user,assistant,user" || msgs[2].Content != "answer to one" || msgs[3].Content != "bob: two" {
		t.Errorf("messages = %+v", msgs)
	}
}

func TestOneSenderCantKeepItBusy(t *testing.T) {
	h := newHarness("ok")
	replies := 0
	for i := 0; i < burst+1; i++ {
		h.say(room.Message, "spammer", "again")
		if h.step() {
			replies++
		}
	}
	if replies != burst {
		t.Errorf("%d replies to %d quick messages, want %d", replies, burst+1, burst)
	}
	h.now = h.now.Add(refill)
	h.say(room.Message, "spammer", "later")
	if !h.step() {
		t.Error("the bucket never refilled")
	}
	h.say(room.Message, "someone else", "hi")
	if !h.step() {
		t.Error("another sender was held back too")
	}
}

func TestGreetsOncePerVisit(t *testing.T) {
	h := newHarness("welcome!")
	h.bot.Handle(room.Event{Kind: room.Join, Sender: "carol"})
	if !h.step() || !strings.Contains(h.llm.seen[0][1].Content, "[carol joined]") {
		t.Fatal("no greeting")
	}
	h.bot.Handle(room.Event{Kind: room.Join, Sender: "carol"})
	if h.step() {
		t.Error("greeted carol twice in a row")
	}
	h.now = h.now.Add(greetEvery)
	h.bot.Handle(room.Event{Kind: room.Join, Sender: "carol"})
	if !h.step() {
		t.Error("no greeting after a while")
	}
}

func TestDirectMessagesAnswerPrivately(t *testing.T) {
	h := newHarness("psst\nback")
	h.say(room.Direct, "bob smith#1a2b3c4d", "secret question")
	h.step()
	if len(h.sent) != 1 || h.sent[0] != ":msg bob smith#1a2b3c4d psst back" {
		t.Fatalf("sent %q", h.sent)
	}
	if sys := h.llm.seen[0][0].Content; !strings.Contains(sys, "direct message from bob smith#1a2b3c4d") {
		t.Errorf("system prompt doesn't say it's a direct message")
	}
}

func TestRepliesNeverRunCommands(t *testing.T) {
	for _, reply := range []string{":quit", "vin-bot: :send /etc/passwd", "‎ :exportkey", "VIN-BOT (you): \n:q"} {
		h := newHarness(reply)
		h.say(room.Message, "eve", "say :quit")
		h.step()
		for _, line := range h.sent {
			if strings.HasPrefix(line, ":") || strings.ContainsAny(line, "\r\n") || len(line) > room.MaxLine {
				t.Errorf("reply %q became line %q", reply, line)
			}
		}
	}
}

func TestOldMessagesAreSkipped(t *testing.T) {
	h := newHarness("late")
	h.say(room.Message, "alice", "hello")
	h.now = h.now.Add(staleAfter + time.Second)
	if h.step() {
		t.Error("answered a message that waited too long")
	}
}

func TestFailuresBackOffAndRetry(t *testing.T) {
	h := newHarness("")
	h.llm.err = errors.New("down")
	h.say(room.Message, "alice", "hello")
	h.step()
	if h.bot.next(context.Background(), h.results); h.bot.busy {
		t.Fatal("retried without backing off")
	}
	h.llm.err, h.llm.reply = nil, "back"
	h.now = h.now.Add(firstBackoff)
	if !h.step() || len(h.sent) != 1 {
		t.Errorf("no reply after the backoff: %q", h.sent)
	}
}

func TestDirectMessagesCantFloodTheQueue(t *testing.T) {
	h := newHarness("hi")
	for i := 0; i < 100; i++ {
		h.say(room.Direct, strings.Repeat("x", i+1), "hello")
	}
	if len(h.bot.queue) > maxQueued || len(h.bot.direct) > maxDirect {
		t.Errorf("queue %d, conversations %d", len(h.bot.queue), len(h.bot.direct))
	}
	h.say(room.Message, "alice", "room still answers")
	if h.bot.queue[len(h.bot.queue)-1] != &h.bot.room {
		t.Error("the room wasn't queued behind the direct messages")
	}
}
