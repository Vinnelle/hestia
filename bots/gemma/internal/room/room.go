package room

import (
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

type Kind int

const (
	Other Kind = iota
	Banner
	Console
	Message
	Direct
	Own
	Join
	Leave
	PeersHead
	PeersEntry
	PeersNone
	Timer
	VerifyCode
	Fingerprint
	BadSignature
	VerifyEnd
	VerifyMiss
)

type Event struct {
	Kind    Kind
	Sender  string
	Nick    string
	Text    string
	Online  int
	Mention bool
}

const MaxLine = 880

var (
	stamp  = regexp.MustCompile(`^\[\d{2}:\d{2}\] `)
	sender = regexp.MustCompile(`^([^()#:@\s][^()#:@]*?)(#[0-9a-f]{8})?((?: \((?:[^()]|\([^()]*\))*\))*)$`)
	tag    = regexp.MustCompile(` \(((?:[^()]|\([^()]*\))*)\)`)
	joined = regexp.MustCompile(`^\* ([^()#:@\s][^()#:@]*?)(#[0-9a-f]{8})? \((?:verified|unverified|\x{26A0} signature invalid)\)(?: \[keeps history\])? joined \((\d+) online\)$`)
	left   = regexp.MustCompile(`^\* ([^()#:@\s][^()#:@]*?)(#[0-9a-f]{8})? (?:left|timed out|went offline) \((\d+) online\)$`)
	online = regexp.MustCompile(` \((\d+) online\)$`)
	peers  = regexp.MustCompile(`^\* online: [^()#:@]+ \(you\), and:$`)
	peer   = regexp.MustCompile(`^\*   ([^()#:@\s][^()#:@]*?)(#[0-9a-f]{8}) \(verify .*\)$`)
	timer  = regexp.MustCompile(`^\* (?:no message timer here|messages here go after) `)
	code   = regexp.MustCompile(`^\* ([^()#:@\s][^()#:@]*?)(#[0-9a-f]{8})?: verify code `)
	signer = regexp.MustCompile(`^\* ([^()#:@\s][^()#:@]*?)(#[0-9a-f]{8})?: signing identity fingerprint ([0-9a-f]{4}(?: [0-9a-f]{4})+) \((verified|unverified|\x{26A0} signature invalid)\)$`)
	ended  = regexp.MustCompile(`^\* read the code out to them over another channel `)
	missed = regexp.MustCompile(`^\* (?:no online peer named '|more than one peer is called )`)
)

func Parse(line string) Event {
	loc := stamp.FindStringIndex(line)
	if loc == nil {
		if strings.HasPrefix(line, "session '") {
			return Event{Kind: Banner, Text: line}
		}
		return Event{Kind: Other, Text: line}
	}
	body := line[loc[1]:]
	if strings.HasPrefix(body, "* ") {
		if m := joined.FindStringSubmatch(body); m != nil {
			n, _ := strconv.Atoi(m[3])
			return Event{Kind: Join, Sender: m[1] + m[2], Nick: m[1], Online: n}
		}
		if m := left.FindStringSubmatch(body); m != nil {
			n, _ := strconv.Atoi(m[3])
			return Event{Kind: Leave, Sender: m[1] + m[2], Nick: m[1], Online: n}
		}
		if m := peer.FindStringSubmatch(body); m != nil {
			return Event{Kind: PeersEntry, Sender: m[1] + m[2], Nick: m[1]}
		}
		if m := code.FindStringSubmatch(body); m != nil {
			return Event{Kind: VerifyCode, Sender: m[1] + m[2], Nick: m[1]}
		}
		if m := signer.FindStringSubmatch(body); m != nil {
			kind := BadSignature
			if m[4] == "verified" {
				kind = Fingerprint
			}
			return Event{Kind: kind, Sender: m[1] + m[2], Nick: m[1], Text: strings.ReplaceAll(m[3], " ", "")}
		}
		switch {
		case ended.MatchString(body):
			return Event{Kind: VerifyEnd}
		case missed.MatchString(body):
			return Event{Kind: VerifyMiss}
		case peers.MatchString(body):
			return Event{Kind: PeersHead}
		case body == "* nobody else yet":
			return Event{Kind: PeersNone}
		case timer.MatchString(body):
			return Event{Kind: Timer, Text: body}
		}
		if m := online.FindStringSubmatch(body); m != nil {
			n, _ := strconv.Atoi(m[1])
			return Event{Kind: Leave, Online: n}
		}
		return Event{Kind: Console, Text: body}
	}
	mention := strings.HasPrefix(body, "@ ")
	head, text, ok := strings.Cut(strings.TrimPrefix(body, "@ "), ": ")
	m := sender.FindStringSubmatch(head)
	if !ok || m == nil {
		return Event{Kind: Console, Text: body}
	}
	kind := Message
	for _, t := range tag.FindAllStringSubmatch(m[3], -1) {
		switch v := t[1]; {
		case v == "you":
			kind = Own
		case v == "→ you":
			if kind != Own {
				kind = Direct
			}
		case strings.HasPrefix(v, "→ "), strings.HasPrefix(v, "via "),
			v == "code compared", v == "codes differ", v == "code not compared":
		default:
			return Event{Kind: Console, Text: body}
		}
	}
	return Event{Kind: kind, Sender: m[1] + m[2], Nick: m[1], Text: text, Mention: mention}
}

func Clean(s string, max int) string {
	var b strings.Builder
	space := false
	for _, r := range s {
		switch {
		case r == utf8.RuneError:
			continue
		case unicode.IsSpace(r):
			space = b.Len() > 0
			continue
		case unicode.IsControl(r), unicode.In(r, unicode.Cf, unicode.Co, unicode.Cs):
			continue
		}
		if space {
			b.WriteByte(' ')
			space = false
		}
		b.WriteRune(r)
	}
	return truncate(strings.TrimLeft(b.String(), ": "), max)
}

func truncate(s string, max int) string {
	const more = "…"
	if len(s) <= max {
		return s
	}
	if max <= len(more) {
		return ""
	}
	cut := max - len(more)
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	if i := strings.LastIndexByte(s[:cut], ' '); i > cut*2/3 {
		cut = i
	}
	return strings.TrimRight(s[:cut], " ") + more
}
