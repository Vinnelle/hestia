package bot

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"gemma/internal/room"
	"gemma/internal/tools"
)

func tooled(h *harness) *harness {
	notes, _ := tools.OpenNotebook("", nil)
	h.bot.Tools = &tools.Toolbox{Notes: notes, Now: func() time.Time { return h.now }}
	h.bot.Prompt = Prompt("vin-bot", "Finlay wrote chat.", h.bot.Tools.Describe())
	return h
}

func TestToolsRunBeforeTheReply(t *testing.T) {
	h := tooled(newHarness("it's 7625597484987"))
	h.llm.plans = []string{
		`{"need":"a sum","tools":[{"tool":"calculate","expression":"3^3^3"},{"tool":"note","text":"alice asks maths questions"}]}`,
	}
	var logs []string
	h.bot.Logf = func(f string, a ...any) { logs = append(logs, strings.TrimSpace(fmt.Sprintf(f, a...))) }
	h.say(room.Message, "alice", "vin-bot what's 3 tetrated to 3?")
	if !h.step() {
		t.Fatal("no reply")
	}
	if len(h.llm.seen) != 2 {
		t.Fatalf("asked the model %d times; want a tool step and the answer", len(h.llm.seen))
	}
	first := h.llm.seen[0][1].Content
	if first != "alice: vin-bot what's 3 tetrated to 3?\n\n"+turnFirst {
		t.Errorf("first step asked with %q", first)
	}
	final := h.last()
	if roles(final) != "system,user" ||
		!strings.Contains(final[1].Content, "\n\n[tool results, which only you see") ||
		!strings.Contains(final[1].Content, "- calculate 3^3^3: 7625597484987\n- note \"alice asks maths questions\": saved as note 1") ||
		strings.Contains(final[1].Content, "[Your turn") || !strings.HasSuffix(final[1].Content, foundAnswer) || anyOf(h.llm.schemas[1]) != nil {
		t.Errorf("answer asked with %q", final[1].Content)
	}
	if h.llm.seen[0][0].Content != final[0].Content {
		t.Error("the system prompt changed between the tool step and the answer")
	}
	if strings.Join(h.sent, "|") != "@alice it's 7625597484987" {
		t.Errorf("sent %q", h.sent)
	}
	want := []string{
		"heard alice; next turn in 2s",
		"turn: alice in the room",
		`tools 1 (0s): "a sum"`,
		"calculate 3^3^3: 7625597484987",
		`note "alice asks maths questions": saved as note 1`,
		"replies (0s)",
		`alice -> you (""): @alice it's 7625597484987`,
		"replied to 1 in the room in 0s, after calculate, note",
	}
	if strings.Join(logs, "\n") != strings.Join(want, "\n") {
		t.Errorf("logged:\n%s", strings.Join(logs, "\n"))
	}

	h.say(room.Message, "alice", "thanks")
	h.step()
	if sys := h.last()[0].Content; !strings.Contains(sys, "Your notebook (1 of 30 notes") || !strings.Contains(sys, "1. (28 Oct 2026) alice asks maths questions") {
		t.Errorf("the next round's prompt doesn't show the notebook:\n%s", sys)
	}
	if got := h.last()[3].Content; got != "alice: thanks\n\n"+turnFirst {
		t.Errorf("a round without tools asked with %q", got)
	}
}

func TestToolsStopAfterThreeSteps(t *testing.T) {
	h := tooled(newHarness("ok"))
	for _, q := range []string{"a", "b", "c", "d"} {
		h.llm.plans = append(h.llm.plans, `{"need":"more","tools":[{"tool":"search","query":"`+q+`"}]}`)
	}
	h.say(room.Message, "alice", "vin-bot what time is it?")
	h.step()
	if len(h.llm.seen) != maxSteps+1 || len(h.llm.plans) != 1 {
		t.Fatalf("asked %d times, %d plans left", len(h.llm.seen), len(h.llm.plans))
	}
	if got := strings.Count(h.last()[1].Content, "\n- search"); got != maxSteps {
		t.Errorf("the answer saw %d search results; want %d", got, maxSteps)
	}
	if anyOf(h.llm.schemas[maxSteps]) != nil || !strings.HasSuffix(h.last()[1].Content, foundAnswer) {
		t.Error("the last step still offered tools")
	}
	if strings.Join(h.sent, "|") != "@alice ok" {
		t.Errorf("sent %q", h.sent)
	}
}

func TestToolsStopWhenNothingIsNew(t *testing.T) {
	look := `{"need":"a fact","tools":[{"tool":"search","query":"6*7"}]}`
	for _, again := range []string{look, `{"need":"Nothing.","tools":[{"tool":"search","query":"more"}]}`} {
		h := tooled(newHarness("42"))
		h.llm.plans = []string{look, again, look}
		h.say(room.Message, "alice", "vin-bot what's 6*7?")
		h.step()
		if len(h.llm.seen) != 3 || anyOf(h.llm.schemas[2]) != nil {
			t.Errorf("after %s: asked %d times, last with %s", again, len(h.llm.seen), h.llm.schemas[len(h.llm.schemas)-1])
		}
		if got := h.last()[1].Content; strings.Count(got, "\n- ") != 1 || !strings.HasSuffix(got, foundAnswer) {
			t.Errorf("after %s: answered with %q", again, got)
		}
		if strings.Join(h.sent, "|") != "@alice 42" {
			t.Errorf("sent %q", h.sent)
		}
	}
}

func TestOnlyWebToolsGetAnotherStep(t *testing.T) {
	h := tooled(newHarness("noted"))
	h.llm.plans = []string{`{"need":"the time and a note","tools":[{"tool":"time","zone":""},{"tool":"note","text":"alice keeps late hours"}]}`}
	h.say(room.Message, "alice", "vin-bot what time is it? remember i'm a night owl")
	h.step()
	if len(h.llm.seen) != 2 || anyOf(h.llm.schemas[1]) != nil || len(h.llm.plans) != 0 {
		t.Fatalf("asked %d times, last with %s", len(h.llm.seen), h.llm.schemas[len(h.llm.schemas)-1])
	}
	if got := h.last()[1].Content; !strings.Contains(got, "\n- time: ") || !strings.Contains(got, "saved as note 1") || !strings.HasSuffix(got, foundAnswer) {
		t.Errorf("answered with %q", got)
	}
}

func TestAnswersWithoutToolsInOneCall(t *testing.T) {
	h := tooled(newHarness("hi"))
	h.say(room.Message, "alice", "hi vin-bot")
	h.step()
	if strings.Join(h.sent, "|") != "@alice hi" || len(h.llm.seen) != 1 {
		t.Fatalf("sent %q after %d asks", h.sent, len(h.llm.seen))
	}
	branches := anyOf(h.llm.schemas[0])
	if len(branches) != 2 || strings.Join(required(branches[0]), ",") != "need,tools" ||
		strings.Join(required(branches[1]), ",") != "need,tools,replies" || strings.Join(nicks(branches[1]), ",") != "alice" {
		t.Errorf("asked with %s", h.llm.schemas[0])
	}

	h.say(room.Direct, "bob", "psst")
	h.step()
	if got := h.sent[len(h.sent)-1]; got != ":msg bob hi" || len(h.llm.seen) != 2 {
		t.Fatalf("sent %q after %d asks", got, len(h.llm.seen))
	}
	if branches := anyOf(h.llm.schemas[1]); len(branches) != 2 || strings.Join(required(branches[1]), ",") != "need,tools,reply" {
		t.Errorf("a direct message asked with %s", h.llm.schemas[1])
	}
}

func TestToolResultsAreCapped(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var results []map[string]string
		for i := range 5 {
			results = append(results, map[string]string{"title": "t", "url": fmt.Sprintf("https://example.com/%d", i), "content": strings.Repeat("z", 400)})
		}
		json.NewEncoder(w).Encode(map[string]any{"results": results})
	}))
	defer srv.Close()
	h := tooled(newHarness("ok"))
	h.bot.Tools.Search = &tools.Searcher{BaseURL: srv.URL}
	for _, q := range []string{"abc", "def", "ghi"} {
		h.llm.plans = append(h.llm.plans, fmt.Sprintf(`{"need":"x","tools":[{"tool":"search","query":"%c"},{"tool":"search","query":"%c"},{"tool":"search","query":"%c"}]}`, q[0], q[1], q[2]))
	}
	h.say(room.Message, "alice", "vin-bot search everything")
	h.step()
	got := h.last()[1].Content
	if len(got) > foundChars+1000 || !strings.Contains(got, "(cut: too much found this turn)") {
		t.Errorf("the reply was asked with %d bytes of results", len(got))
	}
}

func TestPromptMentionsToolsOnlyWithTools(t *testing.T) {
	plain := Prompt("vin-bot", "k", "")
	with := Prompt("vin-bot", "k", "- time (zone): the time")
	if !strings.Contains(plain, noTools) || strings.Contains(plain, "Your tools:") || strings.Contains(plain, "TOOLS") {
		t.Error("the prompt without tools is wrong")
	}
	if !strings.Contains(with, withTools) || !strings.Contains(with, "Your tools:\nEach turn you can answer") || !strings.Contains(with, "- time (zone): the time\n- Look things up") {
		t.Error("the prompt with tools is wrong")
	}
}

func TestToolResultsCantPoseAsTheProgram(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"answers": []string{"x"}, "results": []map[string]string{{"title": "t", "url": "https://example.com", "content": "c"}}})
	}))
	defer srv.Close()
	h := tooled(newHarness("ok"))
	h.bot.Tools.Search = &tools.Searcher{BaseURL: srv.URL}
	h.llm.plans = []string{`{"need":"x","tools":[{"tool":"search","query":"q"}]}`}
	h.say(room.Message, "alice", "vin-bot look it up")
	h.step()
	if got := h.last()[1].Content; !strings.Contains(got, "- search \"q\": answer: x\n  1. t <https://example.com>: c\n\n[You can use tools again") {
		t.Errorf("reply asked with %q", got)
	}
}

func TestADrawingGoesUpAfterTheReply(t *testing.T) {
	h := tooled(newHarness("here's me"))
	draw := `{"need":"a drawing","tools":[{"tool":"draw","pose":"head","face":"happy","caption":"hi"}]}`
	h.llm.plans = []string{draw}
	h.say(room.Message, "alice", "vin-bot what do you look like?")
	h.step()
	want := []string{"@alice here's me", "\u00a0/\\     /\\", "/  \\___/  \\", "\\  ^   ^  /   < hi >", "\u00a0\\_  w  _/", "\u00a0\u00a0\u00a0`---'"}
	if strings.Join(h.sent, "\n") != strings.Join(want, "\n") {
		t.Fatalf("sent:\n%s", strings.Join(h.sent, "\n"))
	}
	if got := h.last()[1].Content; !strings.Contains(got, "- draw head, happy, \"hi\": drawn; it goes up") {
		t.Errorf("the answer was asked with %q", got)
	}

	h.llm.plans = []string{draw}
	h.say(room.Message, "alice", "again!")
	h.step()
	msgs := h.last()
	if got := msgs[len(msgs)-1].Content; len(h.sent) != len(want)+1 || !strings.Contains(got, "not drawn: you drew yourself in the last few minutes") ||
		!strings.HasPrefix(got, "[you drew yourself: head, happy, \"hi\"]\nalice: again!") {
		t.Errorf("sent %q after asking with %q", h.sent[len(want):], got)
	}

	h.llm.plans = []string{draw}
	h.say(room.Direct, "bob", "draw yourself pls")
	h.step()
	if got := h.sent[len(h.sent)-1]; got != ":msg bob \u00a0\u00a0\u00a0`---'" {
		t.Errorf("a direct message's drawing ended with %q", got)
	}
}

func TestAnAnswerThatPromisesIsAskedAgain(t *testing.T) {
	for _, c := range []struct{ reply, said string }{
		{"let me fix that right now with the proper pose! x3", "let me fix"},
		{"on it, bestie! here's the requested pose! x3", "on it"},
		{"*wags tail* here's the requested pose! x3", "here's the requested pose"},
		{"one sec, checking the docs", "one sec"},
		{"okie dokie! *tail wags* checking out my own capabilities now... i'm quite the multi-tasker", "checking out my own capabilities now"},
		{"okie doki! *wags tail* i'll start by making a note of what my main abilities are", "i'll start by"},
		{"on it, bestie! *wags tail* here i am! >w<", "on it"},
		{`here's me x3 /\_/\ ( o.o ) /\_/\`, "text art"},
		{`u got it, bestie! *wags tail* here's a little something for u! x3 /\_/ ( •_•) ⟵ i'm a cool fox / > / \_/`, "text art"},
	} {
		h := tooled(newHarness(c.reply))
		h.llm.plans = []string{"", `{"need":"to draw","tools":[{"tool":"draw","pose":"sit","face":"happy","caption":""}]}`}
		var logs []string
		h.bot.Logf = func(f string, a ...any) { logs = append(logs, fmt.Sprintf(f, a...)) }
		h.say(room.Message, "finlay", "vin-bot draw yourself")
		h.step()
		if len(h.llm.seen) != 3 || anyOf(h.llm.schemas[1]) != nil || strings.Join(required(h.llm.schemas[1]), ",") != "need,tools" {
			t.Errorf("%q: asked %d times, the second with %s", c.reply, len(h.llm.seen), h.llm.schemas[min(1, len(h.llm.schemas)-1)])
			continue
		}
		if strings.Contains(string(h.llm.schemas[1]), `"abilities"`) {
			t.Errorf("%q: the forced step offers abilities, which only describes", c.reply)
		}
		if got := h.llm.seen[1][1].Content; !strings.Contains(got, "\n\n[You started to answer with") || !strings.HasSuffix(got, "]\n\n"+toolsNow) {
			t.Errorf("%q: asked again with %q", c.reply, got)
		}
		if !strings.Contains(strings.Join(logs, "\n"), fmt.Sprintf("has %q with no tool behind it", c.said)) {
			t.Errorf("%q: logged\n%s", c.reply, strings.Join(logs, "\n"))
		}
		if len(h.sent) != 8 || h.sent[0] != "@finlay "+dropArt(c.reply) {
			t.Errorf("%q: sent %q", c.reply, h.sent)
		}
	}

	for _, fine := range []string{"i'm gonna hit 'em with that spicy fox sass! x3", "i'll roast any fed who shows up", "let me know if u need anything"} {
		h := tooled(newHarness(fine))
		h.say(room.Message, "finlay", "vin-bot hi")
		h.step()
		if len(h.llm.seen) != 1 {
			t.Errorf("%q was asked again", fine)
		}
	}

	h := tooled(newHarness("here's the drawing!"))
	h.llm.plans = []string{`{"need":"a drawing","tools":[{"tool":"draw","pose":"sit","face":"happy","caption":""}]}`}
	h.say(room.Message, "finlay", "vin-bot draw yourself")
	h.step()
	if len(h.llm.seen) != 2 || strings.Contains(h.last()[1].Content, "[You started to answer with") {
		t.Errorf("a claim after the tool ran was questioned: %q", h.last()[1].Content)
	}
}

func TestToolCallsRunEvenWhenNeedSaysNothing(t *testing.T) {
	h := tooled(newHarness("here i am"))
	h.llm.plans = []string{`{"need":"nothing","tools":[{"tool":"draw","pose":"wave","face":"happy","caption":"Rawr!"}]}`}
	h.say(room.Message, "finlay", "vin-bot draw yourself waving")
	h.step()
	if len(h.sent) < 2 || h.sent[0] != "@finlay here i am" || !strings.Contains(strings.Join(h.sent, "\n"), "< Rawr! >") {
		t.Errorf("sent %q", h.sent)
	}
}

func TestTextArtIsDropped(t *testing.T) {
	for in, want := range map[string]string{
		`u got it, bestie! *wags tail* here's a little something for u! x3 /\_/ ( •_•) ⟵ i'm a cool fox / > / \_/`: "u got it, bestie! *wags tail* here's a little something for u! x3 i'm a cool fox",
		"rsync -a src/ dst/ and cd / && ls": "rsync -a src/ dst/ and cd / && ls",
		`¯\_(ツ)_/¯ idk :3 >w< (╯°□°)╯︵ ┻━┻`: `¯\_(ツ)_/¯ idk :3 >w< (╯°□°)╯︵ ┻━┻`,
		"see https://example.com/a/b/c ok":  "see https://example.com/a/b/c ok",
	} {
		if got := dropArt(in); got != want {
			t.Errorf("dropArt(%q) = %q", in, got)
		}
	}
}

func TestADrawingGoesUpWithoutAReply(t *testing.T) {
	h := tooled(newHarness(" "))
	h.llm.plans = []string{`{"need":"draw","tools":[{"tool":"draw","pose":"wave","face":"happy","caption":"rawr!"}]}`}
	h.say(room.Message, "finlay", "Draw something")
	h.say(room.Message, "bob", "nice")
	h.step()
	if len(h.sent) != 7 || !strings.Contains(h.sent[2], "< rawr! >") {
		t.Fatalf("sent %q", h.sent)
	}
	if h.bot.drew.IsZero() {
		t.Error("the drawing didn't start the room's wait for the next one")
	}
	turns := h.bot.room.turns
	if got := turns[len(turns)-1].text; got != `[you drew yourself: wave, happy, "rawr!"]` || turns[len(turns)-2].text != "nice" {
		t.Errorf("the room's history ends with %q", got)
	}
}

func TestAbilitiesSayWhenSheCanDrawAndLeadToATool(t *testing.T) {
	h := tooled(newHarness("i can draw, look things up and keep notes"))
	h.llm.plans = []string{`{"need":"draw","tools":[{"tool":"draw","pose":"sit","face":"happy","caption":""}]}`}
	h.say(room.Message, "finlay", "vin-bot draw")
	h.step()
	h.now = h.now.Add(time.Minute)
	asked := len(h.llm.seen)
	h.say(room.Message, "finlay", "vin-bot what can you do?")
	h.step()
	if len(h.llm.seen) != asked+1 || anyOf(h.llm.schemas[asked]) == nil {
		t.Fatalf("asked %d times about her tools, last with %s", len(h.llm.seen)-asked, h.llm.schemas[len(h.llm.schemas)-1])
	}
	got := h.last()[len(h.last())-1].Content
	for _, want := range []string{"finlay: vin-bot what can you do?\n\n[tool results", "\n- abilities: - time (zone): The current date", "\n  - draw (pose, face, caption): Draws you",
		"\n  - You drew in the room a moment ago, so you can't draw here for another 4 minutes.", "[You can use tools again, at most 3 more times"} {
		if !strings.Contains(got, want) {
			t.Errorf("a question about her tools was asked without %q:\n%s", want, got)
		}
	}
	h.say(room.Message, "finlay", "vin-bot what's up?")
	h.step()
	if got := h.last()[len(h.last())-1].Content; strings.Contains(got, "[tool results") {
		t.Errorf("looked at her tools for a plain message: %q", got)
	}

	h = tooled(newHarness("let me draw for u"))
	h.llm.plans = []string{`{"need":"what i can do","tools":[{"tool":"abilities","about":"draw"}]}`, "",
		`{"need":"draw","tools":[{"tool":"draw","pose":"wave","face":"happy","caption":"hi"}]}`}
	h.say(room.Message, "finlay", "vin-bot can you draw?")
	h.step()
	if got := h.llm.seen[1][len(h.llm.seen[1])-1].Content; !strings.Contains(got, "- You can draw right now.") {
		t.Errorf("abilities didn't say drawing is ready: %q", got)
	}
	if len(h.llm.seen) != 4 || len(h.sent) != 8 || !strings.Contains(h.sent[3], "< hi >") {
		t.Errorf("a promise after abilities wasn't followed through: %d asks, sent %q", len(h.llm.seen), h.sent)
	}
}
