package room

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestParse(t *testing.T) {
	cases := []struct {
		line string
		want Event
	}{
		{"session 'vin-moe-party', you are vin-bot (peer 1a2b3c4d). encrypted, over Tor only. :quit or EOF to stop.", Event{Kind: Banner}},
		{"new session id: X", Event{Kind: Other}},
		{"[12:00] bob: hi there", Event{Kind: Message, Sender: "bob", Text: "hi there"}},
		{"[12:00] @ bob: hey vin-bot: you there?", Event{Kind: Message, Sender: "bob", Text: "hey vin-bot: you there?"}},
		{"[12:00] bob smith#1a2b3c4d: hi", Event{Kind: Message, Sender: "bob smith#1a2b3c4d", Text: "hi"}},
		{"[12:00] eve#0badf00d (via bob): relayed", Event{Kind: Message, Sender: "eve#0badf00d", Text: "relayed"}},
		{"[12:00] eve#0badf00d (via bob (code compared)): relayed", Event{Kind: Message, Sender: "eve#0badf00d", Text: "relayed"}},
		{"[12:00] bob (→ you): psst", Event{Kind: Direct, Sender: "bob", Text: "psst"}},
		{"[12:00] vin-bot (you): hello", Event{Kind: Own, Sender: "vin-bot", Text: "hello"}},
		{"[12:00] vin-bot (→ bob) (you): psst back", Event{Kind: Own, Sender: "vin-bot", Text: "psst back"}},
		{"[12:00] * bob (unverified) joined (3 online)", Event{Kind: Join, Sender: "bob", Online: 3}},
		{"[12:00] * bob#1a2b3c4d (verified) [keeps history] joined (2 online)", Event{Kind: Join, Sender: "bob#1a2b3c4d", Online: 2}},
		{"[12:00] * bob left (2 online)", Event{Kind: Leave, Online: 2}},
		{"[12:00] * sandbox: on - from now on chat can only write", Event{Kind: Console}},
		{"[12:00] * bob: spoofed console line", Event{Kind: Console}},
		{"[12:00] bob (admin): unknown tag", Event{Kind: Console}},
		{"[12:00] no separator here", Event{Kind: Console}},
	}
	for _, c := range cases {
		got := Parse(c.line)
		if got.Kind != c.want.Kind || got.Sender != c.want.Sender || got.Online != c.want.Online ||
			(c.want.Text != "" && got.Text != c.want.Text) {
			t.Errorf("Parse(%q) = %+v, want %+v", c.line, got, c.want)
		}
	}
}

func TestCleanNeverStartsACommand(t *testing.T) {
	for _, in := range []string{
		":quit",
		"  :quit",
		": : :send /etc/passwd",
		"‎:quit",
		"⁦​ :quit",
		"\n\t:quit",
		"\x1b[31m:quit",
		" 　:quit",
	} {
		out := Clean(in, MaxLine)
		if strings.HasPrefix(out, ":") || strings.HasPrefix(out, " ") {
			t.Errorf("Clean(%q) = %q starts a command", in, out)
		}
	}
}

func TestCleanMakesOneSafeLine(t *testing.T) {
	out := Clean("hello\r\nworld\x00 ‮evil done\xff", MaxLine)
	if out != "hello world evil done" {
		t.Errorf("Clean = %q", out)
	}
}

func TestCleanCutsLongReplies(t *testing.T) {
	long := strings.Repeat("café ", 400)
	for _, max := range []int{MaxLine, 100, 7} {
		out := Clean(long, max)
		if len(out) > max || !utf8.ValidString(out) || !strings.HasSuffix(out, "…") {
			t.Errorf("Clean(long, %d) = %d bytes %q", max, len(out), out)
		}
	}
	if Clean("short", 100) != "short" {
		t.Error("a short reply changed")
	}
}
