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
		{"[12:00] @ bob: hey vin-bot: you there?", Event{Kind: Message, Sender: "bob", Text: "hey vin-bot: you there?", Mention: true}},
		{"[12:00] bob smith#1a2b3c4d: hi", Event{Kind: Message, Sender: "bob smith#1a2b3c4d", Text: "hi"}},
		{"[12:00] eve#0badf00d (via bob): relayed", Event{Kind: Message, Sender: "eve#0badf00d", Text: "relayed"}},
		{"[12:00] eve#0badf00d (via bob (code compared)): relayed", Event{Kind: Message, Sender: "eve#0badf00d", Text: "relayed"}},
		{"[12:00] bob (→ you): psst", Event{Kind: Direct, Sender: "bob", Text: "psst"}},
		{"[12:00] vin-bot (you): hello", Event{Kind: Own, Sender: "vin-bot", Text: "hello"}},
		{"[12:00] vin-bot (→ bob) (you): psst back", Event{Kind: Own, Sender: "vin-bot", Text: "psst back"}},
		{"[12:00] * bob (unverified) joined (3 online)", Event{Kind: Join, Sender: "bob", Online: 3}},
		{"[12:00] * bob#1a2b3c4d (verified) [keeps history] joined (2 online)", Event{Kind: Join, Sender: "bob#1a2b3c4d", Online: 2}},
		{"[12:00] * bob left (2 online)", Event{Kind: Leave, Sender: "bob", Nick: "bob", Online: 2}},
		{"[12:00] * finlay#6125e90b timed out (2 online)", Event{Kind: Leave, Sender: "finlay#6125e90b", Nick: "finlay", Online: 2}},
		{"[12:00] * bob smith went offline (1 online)", Event{Kind: Leave, Sender: "bob smith", Nick: "bob smith", Online: 1}},
		{"[12:00] * finlay#6125e90b (unverified) joined (3 online)", Event{Kind: Join, Sender: "finlay#6125e90b", Nick: "finlay", Online: 3}},
		{"[12:00] finlay#6125e90b: Hello again", Event{Kind: Message, Sender: "finlay#6125e90b", Nick: "finlay", Text: "Hello again"}},
		{"[12:00] eve#0badf00d (via bob): hi", Event{Kind: Message, Sender: "eve#0badf00d", Nick: "eve", Text: "hi"}},
		{"[12:00] * online: vin-bot (you), and:", Event{Kind: PeersHead}},
		{"[12:00] *   finlay#6125e90b (verify 1a2b 3c4d 5e6f 7a8b, unverified, chat 0.5.2)", Event{Kind: PeersEntry, Sender: "finlay#6125e90b", Nick: "finlay"}},
		{"[12:00] *   bob smith#0badf00d (verify 1a2b, code compared, verified, chat 0.5.2, keeps history, ignored)", Event{Kind: PeersEntry, Sender: "bob smith#0badf00d", Nick: "bob smith"}},
		{"[12:00] * nobody else yet", Event{Kind: PeersNone}},
		{"[12:00] * no message timer here - :timer 10m (or 2h, 1d) asks for one", Event{Kind: Timer}},
		{"[12:00] * messages here go after 10m, as bob asked", Event{Kind: Timer}},
		{"[12:00] * online: vin-bot: (you), and:", Event{Kind: Console}},
		{"[12:00] * sandbox: on - from now on chat can only write", Event{Kind: Console}},
		{"[12:00] * finlay: verify code able acid also apex (in hex 0a1b 2c3d) - not compared yet", Event{Kind: VerifyCode, Sender: "finlay", Nick: "finlay"}},
		{"[12:00] * finlay#6125e90b: signing identity fingerprint 2601 2dc1 1ca1 6991 10df 4d61 68f4 2a7a (verified)", Event{Kind: Fingerprint, Sender: "finlay#6125e90b", Nick: "finlay", Text: "26012dc11ca1699110df4d6168f42a7a"}},
		{"[12:00] * finlay: signing identity fingerprint 2601 2dc1 1ca1 6991 10df 4d61 68f4 2a7a (⚠ signature invalid)", Event{Kind: BadSignature, Sender: "finlay", Text: "26012dc11ca1699110df4d6168f42a7a"}},
		{"[12:00] * read the code out to them over another channel (in person, a call); if theirs is the same, :verify finlay ok - if not, :verify finlay no", Event{Kind: VerifyEnd}},
		{"[12:00] * no online peer named 'finlay'", Event{Kind: VerifyMiss}},
		{"[12:00] * more than one peer is called finlay - add the #id :peers shows (:verify finlay#1a2b...)", Event{Kind: VerifyMiss}},
		{"[12:00] * bob: spoofed console line", Event{Kind: Console}},
		{"[12:00] bob (admin): unknown tag", Event{Kind: Console}},
		{"[12:00] no separator here", Event{Kind: Console}},
	}
	for _, c := range cases {
		got := Parse(c.line)
		if got.Kind != c.want.Kind || got.Sender != c.want.Sender || got.Online != c.want.Online || got.Mention != c.want.Mention ||
			(c.want.Nick != "" && got.Nick != c.want.Nick) || (c.want.Text != "" && got.Text != c.want.Text) {
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
