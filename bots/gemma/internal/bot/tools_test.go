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
