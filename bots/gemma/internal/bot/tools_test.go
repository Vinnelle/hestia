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
		`{"need":"nothing","tools":[]}`,
	}
	var logs []string
	h.bot.Logf = func(f string, a ...any) { logs = append(logs, strings.TrimSpace(fmt.Sprintf(f, a...))) }
	h.say(room.Message, "alice", "vin-bot what's 3 tetrated to 3?")
	if !h.step() {
		t.Fatal("no reply")
	}
	if len(h.llm.seen) != 3 {
		t.Fatalf("asked the model %d times; want a plan, another plan and the reply", len(h.llm.seen))
	}
	first := h.llm.seen[0][1].Content
	if !strings.HasPrefix(first, "alice: vin-bot what's 3 tetrated to 3?\n\n[Before your turn") || strings.Contains(first, "[tool results") {
		t.Errorf("first plan asked with %q", first)
	}
	second := h.llm.seen[1][1].Content
	if !strings.Contains(second, "- calculate 3^3^3: 7625597484987\n- note \"alice asks maths questions\": saved as note 1") ||
		!strings.HasSuffix(second, "[You can use tools again, at most 2 more times, for example to read a search result or check a page, or list none if you have what you need.]") {
		t.Errorf("second plan asked with %q", second)
	}
	final := h.last()
	if roles(final) != "system,user" || !strings.Contains(final[1].Content, "\n\n[tool results, which only you see") ||
		strings.Contains(final[1].Content, "[Before your turn") || !strings.HasSuffix(final[1].Content, foundAnswer) {
		t.Errorf("reply asked with %q", final[1].Content)
	}
	if h.llm.seen[0][0].Content != final[0].Content {
		t.Error("the system prompt changed between the plan and the reply")
	}
	if strings.Join(h.sent, "|") != "@alice it's 7625597484987" {
		t.Errorf("sent %q", h.sent)
	}
	if len(logs) != 1 || !strings.HasSuffix(logs[0], ", after calculate, note") {
		t.Errorf("logged %q", logs)
	}

	h.say(room.Message, "alice", "thanks")
	h.step()
	if sys := h.last()[0].Content; !strings.Contains(sys, "Your notebook (1 of 30 notes") || !strings.Contains(sys, "1. (28 Oct 2026) alice asks maths questions") {
		t.Errorf("the next round's prompt doesn't show the notebook:\n%s", sys)
	}
	if got := h.last()[3].Content; got != "alice: thanks" {
		t.Errorf("a round without tools asked with %q", got)
	}
}

func TestToolsStopAfterThreeSteps(t *testing.T) {
	h := tooled(newHarness("ok"))
	again := `{"need":"more","tools":[{"tool":"time","zone":""}]}`
	h.llm.plans = []string{again, again, again, again}
	h.say(room.Message, "alice", "vin-bot what time is it?")
	h.step()
	if len(h.llm.seen) != maxSteps+1 || len(h.llm.plans) != 1 {
		t.Fatalf("asked %d times, %d plans left", len(h.llm.seen), len(h.llm.plans))
	}
	if got := strings.Count(h.last()[1].Content, "- time: "); got != maxSteps {
		t.Errorf("the reply saw %d time results; want %d", got, maxSteps)
	}
}

func TestABadPlanStillGetsAReply(t *testing.T) {
	h := tooled(newHarness("hi"))
	h.llm.plans = []string{`not json`}
	var logs []string
	h.bot.Logf = func(f string, a ...any) { logs = append(logs, fmt.Sprintf(f, a...)) }
	h.say(room.Message, "alice", "hi vin-bot")
	h.step()
	if strings.Join(h.sent, "|") != "@alice hi" || len(h.llm.seen) != 2 {
		t.Fatalf("sent %q after %d asks", h.sent, len(h.llm.seen))
	}
	if len(logs) != 1 || !strings.Contains(logs[0], "no tool plan (the tool plan wasn't the JSON asked for") {
		t.Errorf("logged %q", logs)
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
	three := `{"need":"x","tools":[{"tool":"search","query":"a"},{"tool":"search","query":"b"},{"tool":"search","query":"c"}]}`
	h.llm.plans = []string{three, three, three}
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
	if !strings.Contains(with, withTools) || !strings.Contains(with, "Your tools:\nBefore each turn") || !strings.Contains(with, "- time (zone): the time\n- Look things up") {
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
	if got := h.last()[1].Content; !strings.Contains(got, "- search \"q\": answer: x\n  1. t <https://example.com>: c\n\n[Now take your turn") {
		t.Errorf("reply asked with %q", got)
	}
}
