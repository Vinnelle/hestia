package bot

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"gemma/internal/llm"
	"gemma/internal/room"
)

type fakeLLM struct {
	reply   string
	raw     string
	err     error
	plans   []string
	seen    [][]llm.Message
	schemas []json.RawMessage
}

func (f *fakeLLM) Ask(ctx context.Context, messages []llm.Message, schema json.RawMessage, maxTokens int) (string, llm.Usage, error) {
	f.seen = append(f.seen, messages)
	f.schemas = append(f.schemas, schema)
	if branches := anyOf(schema); len(branches) == 2 {
		if len(f.plans) > 0 {
			plan := f.plans[0]
			f.plans = f.plans[1:]
			return plan, llm.Usage{}, nil
		}
		schema = branches[1]
	}
	if f.err != nil || f.raw != "" {
		if f.raw != "" {
			return f.raw, llm.Usage{}, f.err
		}
		return f.reply, llm.Usage{}, f.err
	}
	answer := map[string]any{"reply": f.reply}
	if names := nicks(schema); names != nil {
		replies := map[string]roomReply{}
		for _, nick := range names {
			replies[nick] = roomReply{TalkingTo: "you", Reply: f.reply}
		}
		answer = map[string]any{"replies": replies}
	}
	if slices.Contains(required(schema), "need") {
		answer["need"], answer["tools"] = "nothing", []string{}
	}
	out, _ := json.Marshal(answer)
	return string(out), llm.Usage{}, nil
}

func nicks(schema json.RawMessage) []string {
	var s struct {
		Properties struct {
			Replies json.RawMessage `json:"replies"`
		} `json:"properties"`
	}
	json.Unmarshal(schema, &s)
	if s.Properties.Replies == nil {
		return nil
	}
	return required(s.Properties.Replies)
}

func anyOf(schema json.RawMessage) []json.RawMessage {
	var s struct {
		AnyOf []json.RawMessage `json:"anyOf"`
	}
	json.Unmarshal(schema, &s)
	return s.AnyOf
}

func required(schema json.RawMessage) []string {
	var s struct {
		Required []string `json:"required"`
	}
	json.Unmarshal(schema, &s)
	return s.Required
}

type harness struct {
	bot     *Bot
	llm     *fakeLLM
	sent    []string
	asked   int
	now     time.Time
	results chan result
}

func newHarness(reply string) *harness {
	h := &harness{llm: &fakeLLM{reply: reply}, now: time.Date(2026, 10, 28, 12, 0, 0, 0, time.UTC), results: make(chan result, 1)}
	h.bot = &Bot{
		Nick:   "vin-bot",
		Prompt: Prompt("vin-bot", "Finlay wrote chat.", ""),
		LLM:    h.llm,
		Send:   func(line string) error { h.sent = append(h.sent, line); return nil },
		Now:    func() time.Time { return h.now },
	}
	h.bot.init()
	h.now = h.now.Add(alreadyHere)
	return h
}

func nickOf(label string) string {
	nick, _, _ := strings.Cut(label, "#")
	return nick
}

func (h *harness) say(kind room.Kind, sender, text string) {
	h.bot.Handle(room.Event{Kind: kind, Sender: sender, Nick: nickOf(sender), Text: text})
}

func (h *harness) join(label string, online int) {
	h.bot.Handle(room.Event{Kind: room.Join, Sender: label, Nick: nickOf(label), Online: online})
}

func (h *harness) leave(label string, online int) {
	h.bot.Handle(room.Event{Kind: room.Leave, Sender: label, Nick: nickOf(label), Online: online})
}

func (h *harness) step() bool {
	for range 10 {
		wait := h.bot.next(context.Background(), h.results)
		if h.bot.busy {
			h.bot.finish(<-h.results)
			h.now = h.now.Add(spacing)
			return true
		}
		if wait <= 0 || wait > maxHold {
			return false
		}
		h.now = h.now.Add(wait)
	}
	return false
}

func (h *harness) last() []llm.Message {
	return h.llm.seen[len(h.llm.seen)-1]
}

func roles(msgs []llm.Message) string {
	var r []string
	for _, m := range msgs {
		r = append(r, m.Role)
	}
	return strings.Join(r, ",")
}

func TestEachPersonGetsOneReplyToAllTheySaid(t *testing.T) {
	h := newHarness("hi")
	h.say(room.Message, "alice", "hello")
	h.say(room.Message, "bob", "hey bot")
	h.say(room.Message, "alice", "are you there?")
	if !h.step() {
		t.Fatal("no reply")
	}
	if strings.Join(h.sent, "|") != "@alice hi|@bob hi" {
		t.Fatalf("sent %q", h.sent)
	}
	if got := strings.Join(nicks(h.llm.schemas[0]), ","); got != "alice,bob" {
		t.Errorf("asked for replies to %s", got)
	}
	msgs := h.last()
	if roles(msgs) != "system,user" || msgs[1].Content != "alice: hello\nbob: hey bot\nalice: are you there?" {
		t.Errorf("messages = %+v", msgs)
	}
	if !strings.Contains(msgs[0].Content, "Since your last turn, alice, bob spoke or joined.") {
		t.Errorf("the system prompt doesn't name who to answer")
	}

	h.say(room.Message, "alice", "and again")
	h.step()
	msgs = h.last()
	if roles(msgs) != "system,user,assistant,user" || msgs[2].Content != "@alice hi\n@bob hi" {
		t.Errorf("messages = %+v", msgs)
	}
	if got := strings.Join(nicks(h.llm.schemas[1]), ","); got != "alice" {
		t.Errorf("second round answered %s, want only alice", got)
	}
	if h.step() {
		t.Error("replied without anything new")
	}
}

func TestStaysOutOfConversationsNotMeantForIt(t *testing.T) {
	h := newHarness("hi")
	h.llm.raw = `{"replies":{"alice":{"talking_to":"someone else","reply":"butting in"},"bob":{"talking_to":"you","reply":"  "}}}`
	h.say(room.Message, "alice", "how was your day bob?")
	h.bot.Handle(room.Event{Kind: room.Message, Sender: "bob", Nick: "bob", Text: "good! vin-bot, you?", Mention: true})
	if !h.step() {
		t.Fatal("never asked the model")
	}
	if len(h.sent) != 0 {
		t.Fatalf("sent %q", h.sent)
	}
	if got := h.last()[1].Content; got != "alice: how was your day bob?\nbob (to you): good! vin-bot, you?" {
		t.Errorf("messages = %q", got)
	}

	h.llm.raw = ""
	h.say(room.Message, "alice", "nice")
	h.step()
	if got := strings.Join(nicks(h.llm.schemas[1]), ","); got != "alice" {
		t.Errorf("second round answered %s, want only alice", got)
	}
	if msgs := h.last(); roles(msgs) != "system,user" || !strings.HasSuffix(msgs[1].Content, "\nalice: nice") {
		t.Errorf("messages = %+v", msgs)
	}
	if strings.Join(h.sent, "|") != "@alice hi" {
		t.Errorf("sent %q", h.sent)
	}
}

func TestLeavesMessagesAimedAtOthersOut(t *testing.T) {
	h := newHarness("hi")
	h.bot.online["alice"], h.bot.online["bob"], h.bot.online["bobby"] = 1, 1, 1
	h.say(room.Message, "alice", "@Bob look at this")
	h.say(room.Message, "alice", "↪ bob: look at this · lol")
	if h.step() {
		t.Fatal("asked the model about messages for bob")
	}
	h.say(room.Message, "alice", "@bobby hi")
	h.say(room.Message, "alice", "@bob ask vin-bot")
	h.say(room.Message, "alice", "what's chat?")
	h.step()
	want := "alice (to bob): @Bob look at this\nalice (to bob): ↪ bob: look at this · lol\nalice (to bobby): @bobby hi\nalice: @bob ask vin-bot\nalice: what's chat?"
	if got := h.last()[1].Content; got != want {
		t.Errorf("messages = %q", got)
	}
	if strings.Join(h.sent, "|") != "@alice hi" {
		t.Errorf("sent %q", h.sent)
	}
}

func TestMarksTalkAboutItself(t *testing.T) {
	b := &Bot{Nick: "Gemma"}
	for text, want := range map[string]bool{
		"I am going to have to improve Gemmas ability":   true,
		"gemma's replies are so cute":                    true,
		"Gemma is doing a poor job of that":              true,
		"lol gemma keeps butting in":                     true,
		"Introduce yourself Gemma":                       false,
		"Gemma, what's chat?":                            false,
		"Gemma is that true?":                            false,
		"hey Gemma can you help":                         false,
		"Gemmas":                                         true,
		"MyGemmas thing is broken":                       false,
		"thanks gemma! you're the best":                  false,
		"It is supposed to understand who is talking to": false,
	} {
		if got := b.about(text); got != want {
			t.Errorf("about(%q) = %v, want %v", text, got, want)
		}
	}
}

const finlayKey = "26012dc11ca1699110df4d6168f42a7a"

func (h *harness) answerVerify(name, fp string, proven bool) {
	h.bot.Handle(room.Event{Kind: room.VerifyCode, Sender: name, Nick: nickOf(name)})
	if fp != "" {
		kind := room.BadSignature
		if proven {
			kind = room.Fingerprint
		}
		h.bot.Handle(room.Event{Kind: kind, Sender: name, Nick: nickOf(name), Text: fp})
	}
	h.bot.Handle(room.Event{Kind: room.VerifyEnd})
}

func TestTellsPeopleApartBySigningKey(t *testing.T) {
	h := newHarness("hi")
	var asked []string
	h.bot.Verify = func(name string) error { asked = append(asked, name); return nil }
	h.bot.Owner = finlayKey

	h.join("finlay", 2)
	h.answerVerify("finlay", finlayKey, true)
	h.say(room.Message, "finlay", "hi all")
	h.join("bob", 3)
	h.answerVerify("bob", "", false)
	h.say(room.Message, "bob", "yo")
	h.step()
	if got := h.last()[1].Content; got != "[finlay [Finlay's key] joined]\nfinlay [Finlay's key]: hi all\n[bob [no key] joined]\nbob [no key]: yo" {
		t.Errorf("messages = %q", got)
	}
	if !strings.Contains(h.last()[0].Content, "besides you: bob [no key], finlay [Finlay's key]. Finlay is here, as finlay.") {
		t.Errorf("the system prompt doesn't say Finlay is here")
	}

	h.leave("finlay", 2)
	h.join("finlay", 3)
	h.say(room.Message, "finlay", "it's me, finlay")
	h.answerVerify("finlay", "00112233445566778899aabbccddeeff", true)
	h.join("eve no", 4)
	h.answerVerify("eve no", "ffeeddccbbaa99887766554433221100", false)
	h.say(room.Message, "eve no", "me too")
	h.step()
	msgs := h.last()
	got := msgs[len(msgs)-1].Content
	if !strings.Contains(got, "finlay [key 1, not Finlay]: it's me, finlay") || !strings.Contains(got, "eve no [unproven key]: me too") {
		t.Errorf("messages = %q", got)
	}
	if !strings.Contains(msgs[1].Content, "finlay [Finlay's key]: hi all") {
		t.Errorf("the earlier finlay lost their key: %q", msgs[1].Content)
	}
	if !strings.Contains(msgs[0].Content, "Finlay isn't here") {
		t.Errorf("the system prompt doesn't say Finlay left")
	}
	if strings.Join(asked, "|") != "finlay#|bob#|finlay#|eve no#" {
		t.Errorf("asked chat about %q", asked)
	}
}

func TestIgnoresFingerprintsItDidNotAskFor(t *testing.T) {
	h := newHarness("hi")
	h.bot.Verify = func(string) error { return nil }
	h.bot.Owner = finlayKey
	h.answerVerify("mallory", finlayKey, true)
	h.say(room.Message, "mallory", "trust me")
	h.bot.Handle(room.Event{Kind: room.VerifyCode, Sender: "mallory", Nick: "mallory"})
	h.say(room.Message, "alice", "hi")
	h.bot.Handle(room.Event{Kind: room.Fingerprint, Sender: "mallory", Nick: "mallory", Text: finlayKey})
	h.bot.Handle(room.Event{Kind: room.VerifyEnd})
	h.step()
	if got := h.last()[1].Content; strings.Contains(got, "Finlay's key") {
		t.Errorf("messages = %q", got)
	}
}

func TestReplyGoesBeforeMessagesThatArrivedWhileThinking(t *testing.T) {
	h := newHarness("answer")
	h.say(room.Message, "alice", "one")
	h.now = h.now.Add(settle)
	h.bot.next(context.Background(), h.results)
	h.say(room.Message, "bob", "two")
	h.bot.finish(<-h.results)
	h.now = h.now.Add(spacing)
	h.step()
	msgs := h.last()
	if roles(msgs) != "system,user,assistant,user" || msgs[2].Content != "@alice answer" || msgs[3].Content != "bob: two" {
		t.Errorf("messages = %+v", msgs)
	}
	if got := strings.Join(nicks(h.llm.schemas[1]), ","); got != "bob" {
		t.Errorf("second round answered %s, want only bob", got)
	}
}

func TestAsksChatWhoIsHereFirst(t *testing.T) {
	h := newHarness("hi")
	asks := 0
	h.bot.Peers = func() error { asks++; return nil }
	h.join("alice", 2)
	h.join("bob", 3)
	h.bot.room.turns = nil
	h.say(room.Message, "alice", "hi")
	h.say(room.Message, "bob", "yo")
	h.now = h.now.Add(settle)
	h.bot.next(context.Background(), h.results)
	if asks != 1 || h.bot.busy {
		t.Fatalf("asked %d times, busy %v: should ask for :peers and wait", asks, h.bot.busy)
	}
	h.bot.Handle(room.Event{Kind: room.PeersHead})
	h.bot.Handle(room.Event{Kind: room.PeersEntry, Sender: "alice#1a2b3c4d", Nick: "alice"})
	h.bot.Handle(room.Event{Kind: room.PeersEntry, Sender: "carol#0badf00d", Nick: "carol"})
	h.bot.Handle(room.Event{Kind: room.Timer})
	if !h.step() {
		t.Fatal("no reply once chat listed its peers")
	}
	msgs := h.last()
	if !strings.Contains(msgs[0].Content, "besides you: alice, carol.") {
		t.Errorf("system prompt doesn't list chat's peers")
	}
	if !strings.HasSuffix(msgs[1].Content, "[bob left]") {
		t.Errorf("bob isn't recorded as gone: %q", msgs[1].Content)
	}
	if strings.Join(h.sent, "|") != "@alice hi|@bob hi" {
		t.Errorf("sent %q", h.sent)
	}
}

func TestDoesntWaitForeverForPeers(t *testing.T) {
	h := newHarness("hi")
	h.bot.Peers = func() error { return nil }
	h.say(room.Message, "alice", "hi")
	h.now = h.now.Add(settle)
	if wait := h.bot.next(context.Background(), h.results); wait != peersWait || h.bot.busy {
		t.Fatalf("wait %s busy %v", wait, h.bot.busy)
	}
	h.now = h.now.Add(peersWait)
	if !h.step() || len(h.sent) != 1 {
		t.Errorf("no reply after chat didn't answer :peers")
	}
}

func TestGreetsOnlyThoseStillHere(t *testing.T) {
	h := newHarness("welcome!")
	h.join("carol", 2)
	h.join("dave", 3)
	h.leave("dave", 2)
	if !h.step() || strings.Join(h.sent, "|") != "@carol welcome!" {
		t.Fatalf("sent %q", h.sent)
	}
	h.leave("carol", 1)
	h.join("carol", 2)
	if h.step() {
		t.Error("greeted carol twice in a row")
	}
	h.leave("carol", 1)
	h.now = h.now.Add(greetEvery)
	h.join("carol", 2)
	if !h.step() {
		t.Error("no greeting after a while")
	}
}

func TestOneSenderCantKeepItBusy(t *testing.T) {
	h := newHarness("ok")
	for range burst {
		h.say(room.Message, "spammer", "again")
	}
	if !h.step() || len(h.sent) != 1 {
		t.Fatalf("%d replies to a quick burst, want 1", len(h.sent))
	}
	h.say(room.Message, "spammer", "and again")
	if h.step() {
		t.Error("replied past the burst")
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

func TestWaitsForAQuietMoment(t *testing.T) {
	h := newHarness("hi")
	h.say(room.Message, "alice", "hello")
	if wait := h.bot.next(context.Background(), h.results); wait != settle || h.bot.busy {
		t.Fatalf("wait %s busy %v", wait, h.bot.busy)
	}
	gap := settle - 500*time.Millisecond
	var elapsed time.Duration
	for i := 0; elapsed+settle <= maxHold; i++ {
		h.now, elapsed = h.now.Add(gap), elapsed+gap
		h.say(room.Message, fmt.Sprintf("p%d", i), "hi")
		if h.bot.next(context.Background(), h.results); h.bot.busy {
			t.Fatalf("started answering before p%d's message settled", i)
		}
	}
	if wait := h.bot.next(context.Background(), h.results); wait != maxHold-elapsed {
		t.Errorf("wait %s: the first message should wait at most %s", wait, maxHold)
	}
	if !h.step() || len(h.sent) != maxAddressed {
		t.Errorf("sent %q", h.sent)
	}
}

type fakeJudge struct {
	mu      sync.Mutex
	answers []string
	seen    [][]llm.Message
}

func (f *fakeJudge) Ask(ctx context.Context, messages []llm.Message, schema json.RawMessage, maxTokens int) (string, llm.Usage, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.seen = append(f.seen, messages)
	next := f.answers[0]
	f.answers = f.answers[1:]
	if next == "" {
		return "", llm.Usage{}, errors.New("down")
	}
	return `"` + next + `"`, llm.Usage{}, nil
}

func TestGuessesWhetherMoreIsComing(t *testing.T) {
	h := newHarness("chat is a terminal chat")
	judge := &fakeJudge{answers: []string{"more", "finished"}}
	h.bot.Judge, h.bot.ctx, h.bot.guesses = judge, context.Background(), make(chan guess, 4)
	wait := func() time.Duration { return h.bot.next(context.Background(), h.results) }

	h.say(room.Message, "alice", "hey vin-bot")
	if w := wait(); w != moreWait || h.bot.busy {
		t.Fatalf("waits %s before the guess; want %s", w, moreWait)
	}
	h.bot.guessed(<-h.bot.guesses)
	if w := wait(); w != moreWait || h.bot.busy {
		t.Fatalf("waits %s after guessing more is coming; want %s", w, moreWait)
	}
	if got := judge.seen[0][1].Content; got != "alice: hey vin-bot\n\n[Is alice about to send more after \"hey vin-bot\", or finished?]" {
		t.Errorf("asked %q", got)
	}

	h.now = h.now.Add(4 * time.Second)
	h.say(room.Message, "alice", "what's chat?")
	if w := wait(); w != moreWait || h.bot.busy {
		t.Fatalf("waits %s after the second message; want %s again", w, moreWait)
	}
	h.bot.guessed(<-h.bot.guesses)
	if wait(); !h.bot.busy {
		t.Fatal("didn't answer as soon as alice looked done")
	}
	h.bot.finish(<-h.results)
	if strings.Join(h.sent, "|") != "@alice chat is a terminal chat" || h.last()[1].Content != "alice: hey vin-bot\nalice: what's chat?" {
		t.Errorf("sent %q for %q", h.sent, h.last()[1].Content)
	}

	judge.mu.Lock()
	judge.answers = []string{"finished", "more", ""}
	judge.mu.Unlock()
	h.now = h.now.Add(time.Minute)
	h.say(room.Message, "bob", "vin-bot is")
	h.say(room.Message, "bob", "vin-bot is it e2e?")
	first, second := <-h.bot.guesses, <-h.bot.guesses
	if first.seq > second.seq {
		first, second = second, first
	}
	h.bot.guessed(first)
	if w := wait(); w != moreWait || h.bot.busy {
		t.Errorf("an older message's guess moved the turn: waits %s", w)
	}
	h.bot.guessed(second)
	h.now = h.now.Add(time.Second)
	h.say(room.Message, "bob", "and signed?")
	h.bot.guessed(<-h.bot.guesses)
	if w := wait(); w != settle || h.bot.busy {
		t.Errorf("waits %s when the guess failed; want %s", w, settle)
	}
}

func TestANewcomerWhoSpeaksGetsOneReply(t *testing.T) {
	h := newHarness("welcome, and hi")
	h.join("finlay", 2)
	if wait := h.bot.next(context.Background(), h.results); wait != joinGrace || h.bot.busy {
		t.Fatalf("wait %s busy %v: should give a newcomer time to speak", wait, h.bot.busy)
	}
	h.now = h.now.Add(4 * time.Second)
	h.say(room.Message, "finlay", "Hello!")
	if !h.step() || strings.Join(h.sent, "|") != "@finlay welcome, and hi" {
		t.Fatalf("sent %q", h.sent)
	}
	if last := h.last()[1].Content; last != "[finlay joined]\nfinlay: Hello!" {
		t.Errorf("last turn = %q", last)
	}
	if h.step() {
		t.Error("replied twice")
	}
}

func TestDoesntGreetWhoWasAlreadyHere(t *testing.T) {
	h := newHarness("hi")
	h.bot.started = h.now
	h.join("finlay", 2)
	if h.step() {
		t.Error("greeted someone who was there before the bot")
	}
	h.say(room.Message, "finlay", "Hello!")
	if !h.step() || len(h.sent) != 1 {
		t.Fatalf("sent %q", h.sent)
	}
	msgs := h.last()
	if msgs[1].Content != "finlay: Hello!" || !strings.Contains(msgs[0].Content, "besides you: finlay.") {
		t.Errorf("messages = %+v", msgs)
	}
}

func TestAReconnectIsStillOnePerson(t *testing.T) {
	h := newHarness("hi")
	h.join("finlay", 2)
	h.step()
	h.join("finlay#6125e90b", 3)
	if h.step() {
		t.Error("greeted a reconnect")
	}
	h.say(room.Message, "finlay#6125e90b", "Hello again")
	h.step()
	msgs := h.last()
	for _, m := range msgs[1:] {
		if strings.Contains(m.Content, "#6125e90b") || strings.Count(m.Content, "[finlay joined]") > 1 {
			t.Errorf("the model saw two finlays: %q", m.Content)
		}
	}
	if last := msgs[len(msgs)-1].Content; last != "finlay: Hello again" {
		t.Errorf("last turn = %q", last)
	}
	if !strings.Contains(msgs[0].Content, "besides you: finlay.\n") {
		t.Errorf("finlay isn't listed once")
	}

	h.leave("finlay#0badf00d", 2)
	h.say(room.Message, "finlay", "still me")
	h.step()
	msgs = h.last()
	if strings.Contains(msgs[len(msgs)-1].Content, "left") || !strings.Contains(msgs[0].Content, "besides you: finlay.\n") {
		t.Errorf("the old connection timing out looked like finlay leaving: %+v", msgs)
	}

	h.leave("finlay", 1)
	h.join("alice", 2)
	h.step()
	msgs = h.last()
	if last := msgs[len(msgs)-1].Content; !strings.Contains(last, "[finlay left]\n[alice joined]") {
		t.Errorf("last turn = %q", last)
	}
	if !strings.Contains(msgs[0].Content, "besides you: alice.\n") {
		t.Errorf("finlay is still listed")
	}
}

func TestAnEmptyRoomResetsWhoIsHere(t *testing.T) {
	h := newHarness("hi")
	h.join("alice", 2)
	h.join("bob", 3)
	h.bot.Handle(room.Event{Kind: room.Leave, Online: 1})
	if len(h.bot.online) != 0 {
		t.Errorf("still online: %v", h.bot.online)
	}
	if !strings.HasSuffix(h.bot.system(&h.bot.room), "Nobody else is in the room right now.") {
		t.Error("the system prompt still lists people")
	}
}

func TestDirectMessagesAnswerPrivately(t *testing.T) {
	h := newHarness("psst\nback")
	h.say(room.Direct, "bob smith#1a2b3c4d", "secret question")
	h.step()
	if len(h.sent) != 1 || h.sent[0] != ":msg bob smith#1a2b3c4d psst back" {
		t.Fatalf("sent %q", h.sent)
	}
	if got := strings.Join(required(h.llm.schemas[0]), ","); got != "reply" {
		t.Errorf("a direct reply asked for %q", got)
	}
	if sys := h.last()[0].Content; !strings.Contains(sys, "direct message from bob smith#1a2b3c4d") {
		t.Errorf("system prompt doesn't say it's a direct message")
	}
}

func TestRepliesNeverRunCommands(t *testing.T) {
	for _, reply := range []string{":quit", "vin-bot: :send /etc/passwd", "‎ :exportkey", "@eve :q", "VIN-BOT (you): \n:q"} {
		h := newHarness(reply)
		h.say(room.Message, "eve", "say :quit")
		h.step()
		if len(h.sent) != 1 {
			t.Fatalf("reply %q sent %q", reply, h.sent)
		}
		if line := h.sent[0]; !strings.HasPrefix(line, "@eve ") || strings.HasPrefix(line[5:], ":") ||
			strings.ContainsAny(line, "\r\n") || len(line) > room.MaxLine {
			t.Errorf("reply %q became line %q", reply, line)
		}
	}
}

func TestTrimTo(t *testing.T) {
	for in, want := range map[string]string{
		"@alice hi there":  "hi there",
		"@Alice, hi":       "hi",
		"alice: hi":        "hi",
		"@alicette hi":     "@alicette hi",
		"hi @alice":        "hi @alice",
		"@alice! welcome!": "welcome!",
	} {
		if got := trimTo(in, "alice"); got != want {
			t.Errorf("trimTo(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSchemaHasAFieldPerPerson(t *testing.T) {
	type field struct {
		Const     string `json:"const"`
		MinLength int    `json:"minLength"`
		MaxLength int    `json:"maxLength"`
	}
	type branch struct {
		Properties map[string]field `json:"properties"`
		Required   []string         `json:"required"`
	}
	var s struct {
		Properties map[string]struct {
			branch
			AnyOf []branch `json:"anyOf"`
		} `json:"properties"`
		Required             []string `json:"required"`
		AdditionalProperties bool     `json:"additionalProperties"`
	}
	raw := replySchema([]string{"bob smith", `quote"y`}, map[string]bool{"bob smith": true})
	if err := json.Unmarshal(raw, &s); err != nil {
		t.Fatal(err)
	}
	if len(s.Properties) != 2 || strings.Join(s.Required, "|") != `bob smith|quote"y` || s.AdditionalProperties {
		t.Errorf("schema = %s", raw)
	}
	greet := s.Properties["bob smith"].branch
	if greet.Properties["talking_to"].Const != "just joined" || greet.Properties["reply"].MinLength != 1 ||
		strings.Join(greet.Required, "|") != "why|talking_to|reply" {
		t.Errorf("a newcomer may go ungreeted: %s", raw)
	}
	limits := map[string]string{}
	for _, b := range s.Properties[`quote"y`].AnyOf {
		r := b.Properties["reply"]
		limits[b.Properties["talking_to"].Const] = fmt.Sprintf("%d-%d", r.MinLength, r.MaxLength)
	}
	want := map[string]string{"you": fmt.Sprintf("1-%d", replyChars), "someone else": "0-0", "everyone": fmt.Sprintf("0-%d", replyChars)}
	if fmt.Sprint(limits) != fmt.Sprint(want) {
		t.Errorf("reply lengths by talking_to = %v, want %v", limits, want)
	}
	if w, k, r := strings.Index(string(raw), `"why"`), strings.Index(string(raw), `"talking_to"`), strings.Index(string(raw), `"reply"`); w > k || k > r {
		t.Error("why, then talking_to, then reply: the model works out who it's for before writing")
	}
}

func TestBadJSONBacksOff(t *testing.T) {
	h := newHarness("")
	h.llm.raw = "not json"
	h.say(room.Message, "alice", "hello")
	h.step()
	if len(h.sent) != 0 || h.bot.failures != 1 || !h.bot.room.pending {
		t.Errorf("sent %q, failures %d, pending %v", h.sent, h.bot.failures, h.bot.room.pending)
	}
}

func TestTooManyPeopleAtOnce(t *testing.T) {
	h := newHarness("hi")
	for _, nick := range []string{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j"} {
		h.say(room.Message, nick, "hi")
	}
	h.step()
	if len(h.sent) != maxAddressed {
		t.Errorf("%d replies, want %d", len(h.sent), maxAddressed)
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
	for i := range 100 {
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
