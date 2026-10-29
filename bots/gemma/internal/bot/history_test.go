package bot

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gemma/internal/room"
)

func openHistory(t *testing.T, path string, key byte) *History {
	t.Helper()
	h, err := OpenHistory(path, bytes.Repeat([]byte{key}, 32))
	if err != nil {
		t.Fatal(err)
	}
	return h
}

func TestHistoryLastsARestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	const keyA, keyB, keyC = "00112233445566778899aabbccddeeff", "ffeeddccbbaa99887766554433221100", "0123456789abcdef0123456789abcdef"

	h := newHarness("hi")
	h.bot.History = openHistory(t, path, 1)
	h.bot.Verify = func(string) error { return nil }
	h.join("alice", 2)
	h.answerVerify("alice", keyA, true)
	h.say(room.Message, "alice", "my favourite colour is green")
	h.say(room.Message, "bob", "hello")
	h.say(room.Direct, "carol", "a secret")
	for h.step() {
	}
	h.bot.keep()
	if data, _ := os.ReadFile(path); len(data) == 0 || bytes.Contains(data, []byte("green")) {
		t.Fatalf("the history isn't sealed: %q", data)
	}

	h2 := newHarness("hey")
	h2.bot.History = openHistory(t, path, 1)
	h2.bot.Verify = func(string) error { return nil }
	h2.bot.restore()
	if h2.step() {
		t.Fatal("answered what was said before the restart")
	}
	if len(h2.bot.direct) != 0 {
		t.Error("kept a direct message")
	}
	h2.join("alice", 2)
	h2.answerVerify("alice", keyB, true)
	h2.join("bob", 3)
	h2.answerVerify("bob", keyC, true)
	h2.say(room.Message, "alice", "i'm alice")
	h2.say(room.Message, "bob", "it's bob")
	if !h2.step() {
		t.Fatal("no reply after the restart")
	}
	msgs := h2.last()
	if roles(msgs) != "system,user,assistant,user" {
		t.Fatalf("messages = %+v", msgs)
	}
	if msgs[1].Content != "[alice [key 1] joined]\nalice [key 1]: my favourite colour is green\nbob: hello" {
		t.Errorf("before the restart: %q", msgs[1].Content)
	}
	if !strings.HasPrefix(msgs[3].Content, "[you restarted; the lines above are from before 28 Oct 12:02 UTC]\n") ||
		!strings.Contains(msgs[3].Content, "alice [key 2]: i'm alice") || !strings.Contains(msgs[3].Content, "bob [key 3]: it's bob") {
		t.Errorf("after the restart: %q", msgs[3].Content)
	}
	for _, m := range msgs {
		if strings.Contains(m.Content, "a secret") {
			t.Error("a direct message came back")
		}
	}
}

func TestUnreadableHistoryIsSetAside(t *testing.T) {
	path := filepath.Join(t.TempDir(), "history")
	h := newHarness("hi")
	h.bot.History = openHistory(t, path, 1)
	h.say(room.Message, "alice", "hello")
	h.step()
	h.bot.keep()

	for _, wrong := range []*History{openHistory(t, path, 2), openHistory(t, path, 1)} {
		h2 := newHarness("hi")
		h2.bot.History = wrong
		h2.bot.restore()
		if len(h2.bot.room.turns) != 0 {
			t.Errorf("restored %d lines from a history it can't open", len(h2.bot.room.turns))
		}
		if _, err := os.Stat(path + ".bad"); err != nil {
			t.Errorf("the history wasn't set aside: %v", err)
		}
		os.WriteFile(path, []byte("not sealed"), 0o600)
	}
}

func TestRejoiningForgetsWhoWasHere(t *testing.T) {
	h := newHarness("hi")
	h.join("alice", 2)
	h.join("bob", 3)
	h.now = h.now.Add(alreadyHere)
	h.bot.Handle(room.Event{Kind: room.Banner})
	if len(h.bot.online) != 0 {
		t.Errorf("still counts %v as here", h.bot.online)
	}
	turns := len(h.bot.room.turns)
	h.join("alice", 2)
	if h.bot.online["alice"] != 1 || len(h.bot.room.turns) != turns {
		t.Errorf("a join right after rejoining counted %d, added %d lines", h.bot.online["alice"], len(h.bot.room.turns)-turns)
	}
}
