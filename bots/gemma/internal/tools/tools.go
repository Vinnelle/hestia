package tools

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"
	_ "time/tzdata"
)

const (
	MaxCalls  = 3
	needChars = 160
	maxZone   = 64
)

type Call struct {
	Tool       string `json:"tool"`
	Query      string `json:"query,omitempty"`
	URL        string `json:"url,omitempty"`
	Find       string `json:"find,omitempty"`
	Zone       string `json:"zone,omitempty"`
	Expression string `json:"expression,omitempty"`
	Text       string `json:"text,omitempty"`
	Number     int    `json:"number,omitempty"`
	Page       string `json:"page,omitempty"`
	Pose       string `json:"pose,omitempty"`
	Face       string `json:"face,omitempty"`
	Caption    string `json:"caption,omitempty"`
	About      string `json:"about,omitempty"`
}

type Plan struct {
	Need  string `json:"need"`
	Tools []Call `json:"tools"`
}

type Toolbox struct {
	Search *Searcher
	Read   *Reader
	Docs   *Docs
	Notes  *Notebook
	Now    func() time.Time
}

type tool struct {
	name   string
	args   []arg
	about  string
	more   string
	status func() string
	run    func(ctx context.Context, c Call) (string, error)
}

type arg struct {
	name   string
	schema string
}

func text(name string, minLen, maxLen int) arg {
	return arg{name, fmt.Sprintf(`{"type":"string","minLength":%d,"maxLength":%d}`, minLen, maxLen)}
}

func choice(name string, options []string) arg {
	list, _ := json.Marshal(options)
	return arg{name, `{"enum":` + string(list) + `}`}
}

func (t *Toolbox) list() []tool {
	var list []tool
	if t.Search != nil {
		list = append(list, tool{
			name:  "search",
			args:  []arg{text("query", 1, maxQuery)},
			about: "search (query): search the web. You get titles, links and snippets; read a result when its snippet isn't enough.",
			more: "Searches the web through SearXNG, a search engine on Finlay's cluster, and gives you the top 5 results (title, link and snippet) " +
				"and any instant answer. Searches leave from the cluster, never from whoever asked. You get another step after a search, to read a result.",
			run: func(ctx context.Context, c Call) (string, error) { return t.Search.Search(ctx, c.Query) },
		})
	}
	if t.Read != nil {
		list = append(list, tool{
			name:  "read",
			args:  []arg{text("url", 1, maxURL), text("find", 0, 100)},
			about: "read (url, find): open a web page and read its text. find is a few words to look for on a long page, or empty for its start.",
			more: "Opens a public http or https page over Tor and gives you its main text without menus, scripts or footers: 3,000 characters from the start, " +
				"or the lines that mention find's words. It can't open private addresses or anything behind a login, only reads text, HTML, JSON or XML " +
				"up to 2 MiB, and some sites block Tor. You get another step after reading.",
			run: func(ctx context.Context, c Call) (string, error) { return t.Read.Read(ctx, c.URL, c.Find) },
		})
	}
	if t.Docs != nil {
		list = append(list, tool{
			name:  "docs",
			args:  []arg{text("query", 1, maxQuery)},
			about: "docs (query): search chat's own documentation, at the version you run, for a command, setting, option or how something works. You get the best-matching sections and a link to each.",
			more: "Searches chat's documentation, fetched over Tor from github.com/Vinnelle/chat at the version you run: the README, every page in docs/ " +
				"(getting started, usage, security, routing, files and pictures, saves, the wire protocol, architecture, building, releasing) and SECURITY.md. " +
				"You get the 3 sections that match the most of your words, with a GitHub link to each. It matches words, not meaning, so use the words the docs would.",
			status: t.Docs.Loaded,
			run:    func(ctx context.Context, c Call) (string, error) { return t.Docs.Search(ctx, c.Query) },
		})
	}
	if t.Read != nil {
		list = append(list, tool{
			name:  "manual",
			args:  []arg{text("page", 1, maxPageName), text("find", 0, 100)},
			about: "manual (page, find): the tldr examples and the manual page for a Linux command, config file or function, like rsync, sshd_config or systemd.service. find is a few words to look for in the manual, such as an option, or empty for its start.",
			more: "Fetches, over Tor, the tldr-pages examples for a command and its manual page from man.archlinux.org, which covers most Linux tools, " +
				"config files and functions. page is one name, with (5) or .5 after it for a section; find picks the paragraphs about an option, best first.",
			run: func(ctx context.Context, c Call) (string, error) { return t.Read.Manual(ctx, c.Page, c.Find) },
		})
	}
	list = append(list,
		tool{
			name:  "time",
			args:  []arg{text("zone", 0, maxZone)},
			about: "time (zone): the current date and time. zone is a time zone name like Europe/London or America/New_York, or empty for UTC.",
			more:  "The current date and time anywhere, by time zone name (Europe/London, America/New_York, Asia/Tokyo), or in UTC. You don't otherwise know the date.",
			run:   func(ctx context.Context, c Call) (string, error) { return t.time(c.Zone) },
		},
		tool{
			name:  "calculate",
			args:  []arg{text("expression", 1, maxExpression)},
			about: "calculate (expression): exact arithmetic with + - * / % ^, parentheses, ! for factorials, pi, e, and sqrt, cbrt, abs, ln, log10, log2, exp, sin, cos, tan, asin, acos, atan, floor, ceil, round, min and max.",
			more:  "Works out a sum exactly with a small parser rather than in your head, with the operators and functions above, including huge numbers like 3^3^3.",
			run:   func(ctx context.Context, c Call) (string, error) { return Calculate(c.Expression) },
		},
		tool{
			name:  "draw",
			args:  []arg{choice("pose", Poses), choice("face", Faces), text("caption", 0, CaptionChars)},
			about: "draw (pose, face, caption): draw yourself as a fox in ASCII art, which goes up on its own lines right after your reply. pose sign holds up a sign with the caption on it; in the others the caption is a few words you say, or empty.",
			more: fmt.Sprintf("Draws you as a small ASCII fox, sent on its own lines right after your reply. Poses: %s (sign holds up a sign with the caption on it). "+
				"Faces: %s. The caption is up to %d plain characters in a speech bubble, or empty, though a sign needs one. "+
				"One drawing a turn, and in the room at most one every 5 minutes.", strings.Join(Poses, ", "), strings.Join(Faces, ", "), CaptionChars),
			run: func(ctx context.Context, c Call) (string, error) {
				lines, err := Draw(c.Pose, c.Face, c.Caption)
				return strings.Join(lines, "\n"), err
			},
		})
	if t.Notes != nil {
		list = append(list,
			tool{
				name:   "note",
				args:   []arg{text("text", 1, NoteChars)},
				about:  fmt.Sprintf("note (text): write a note of up to %d characters in your notebook.", NoteChars),
				more:   fmt.Sprintf("Writes a note in your notebook, which lasts across restarts: up to %d notes of %d characters, numbered for good. You see the whole notebook every turn.", MaxNotes, NoteChars),
				status: t.notesLeft,
				run:    func(ctx context.Context, c Call) (string, error) { return t.Notes.Add(c.Text, t.now()) },
			},
			tool{
				name:   "forget",
				args:   []arg{{"number", `{"type":"integer","minimum":1}`}},
				about:  "forget (number): cross out a note in your notebook by its number.",
				more:   "Crosses out a note by its number, which frees its space.",
				status: t.notesLeft,
				run:    func(ctx context.Context, c Call) (string, error) { return t.Notes.Forget(c.Number) },
			})
	}
	names := []string{"all"}
	for _, tl := range list {
		names = append(names, tl.name)
	}
	return append(list, tool{
		name:  "abilities",
		args:  []arg{choice("about", append(names, "abilities"))},
		about: "abilities (about): what each of your tools can do in detail, its limits, and whether it's ready right now. about is one tool's name, or all.",
		more:  "Tells you what your tools can do, their limits, and whether each is ready right now. You get another step after it, to use what you found.",
		run:   func(ctx context.Context, c Call) (string, error) { return t.abilities(c.About) },
	})
}

func (t *Toolbox) notesLeft() string {
	return fmt.Sprintf("%d of %d notes used", len(t.Notes.Notes()), MaxNotes)
}

func (t *Toolbox) abilities(about string) (string, error) {
	var b strings.Builder
	for _, tl := range t.list() {
		if about != "all" && about != tl.name {
			continue
		}
		fmt.Fprintf(&b, "- %s: %s", strings.SplitN(tl.about, ":", 2)[0], tl.more)
		if tl.status != nil {
			fmt.Fprintf(&b, " Now: %s.", tl.status())
		}
		b.WriteByte('\n')
	}
	if b.Len() == 0 {
		return "", fmt.Errorf("there's no tool called %q", about)
	}
	return strings.TrimSpace(b.String()), nil
}

func (t *Toolbox) now() time.Time {
	if t.Now != nil {
		return t.Now()
	}
	return time.Now()
}

func (t *Toolbox) time(zone string) (string, error) {
	zone = strings.TrimSpace(zone)
	loc := time.UTC
	if zone != "" && !strings.EqualFold(zone, "UTC") {
		var err error
		if loc, err = time.LoadLocation(zone); err != nil {
			return "", fmt.Errorf("unknown time zone %q; use a name like Europe/London", zone)
		}
	}
	now := t.now().In(loc)
	return now.Format("Monday 2 January 2006, 15:04 MST (UTC-07:00)") + " in " + loc.String(), nil
}

func (t *Toolbox) Describe() string {
	var b strings.Builder
	for _, tl := range t.list() {
		fmt.Fprintf(&b, "- %s\n", tl.about)
	}
	return strings.TrimSpace(b.String())
}

var NeedSchema = text("need", 1, needChars).schema

func (t *Toolbox) Schema(skip ...string) json.RawMessage {
	var b strings.Builder
	for _, tl := range t.list() {
		if slices.Contains(skip, tl.name) {
			continue
		}
		if b.Len() > 0 {
			b.WriteByte(',')
		}
		fmt.Fprintf(&b, `{"type":"object","properties":{"tool":{"const":%q}`, tl.name)
		required := []string{"tool"}
		for _, a := range tl.args {
			fmt.Fprintf(&b, `,%q:%s`, a.name, a.schema)
			required = append(required, a.name)
		}
		names, _ := json.Marshal(required)
		fmt.Fprintf(&b, `},"required":%s,"additionalProperties":false}`, names)
	}
	return json.RawMessage(fmt.Sprintf(`{"type":"object","properties":{"need":%s,"tools":{"type":"array","minItems":1,"maxItems":%d,"items":{"anyOf":[%s]}}},"required":["need","tools"],"additionalProperties":false}`,
		NeedSchema, MaxCalls, b.String()))
}

func ParsePlan(reply string) (Plan, error) {
	var p Plan
	if err := json.Unmarshal([]byte(reply), &p); err != nil {
		return Plan{}, fmt.Errorf("the tool plan wasn't the JSON asked for: %w", err)
	}
	if len(p.Tools) > MaxCalls {
		p.Tools = p.Tools[:MaxCalls]
	}
	return p, nil
}

type Result struct {
	Call Call
	Text string
	Err  error
	Took time.Duration
}

func (t *Toolbox) Run(ctx context.Context, calls []Call) []Result {
	byName := map[string]tool{}
	for _, tl := range t.list() {
		byName[tl.name] = tl
	}
	results := make([]Result, len(calls))
	var wg sync.WaitGroup
	for i, c := range calls {
		wg.Go(func() {
			r := Result{Call: c}
			start := time.Now()
			if tl, ok := byName[c.Tool]; !ok {
				r.Err = errors.New("there's no such tool")
			} else {
				r.Text, r.Err = tl.run(ctx, c)
			}
			r.Took = time.Since(start)
			results[i] = r
		})
	}
	wg.Wait()
	return results
}

func (c Call) String() string {
	switch c.Tool {
	case "search":
		return fmt.Sprintf("search %q", c.Query)
	case "read":
		if c.Find != "" {
			return fmt.Sprintf("read <%s> looking for %q", c.URL, c.Find)
		}
		return fmt.Sprintf("read <%s>", c.URL)
	case "docs":
		return fmt.Sprintf("docs %q", c.Query)
	case "manual":
		if c.Find != "" {
			return fmt.Sprintf("manual %q looking for %q", c.Page, c.Find)
		}
		return fmt.Sprintf("manual %q", c.Page)
	case "draw":
		if c.Caption != "" {
			return fmt.Sprintf("draw %s, %s, %q", c.Pose, c.Face, c.Caption)
		}
		return fmt.Sprintf("draw %s, %s", c.Pose, c.Face)
	case "abilities":
		if c.About == "" || c.About == "all" {
			return "abilities"
		}
		return "abilities of " + c.About
	case "time":
		if c.Zone == "" {
			return "time"
		}
		return "time in " + c.Zone
	case "calculate":
		return "calculate " + c.Expression
	case "note":
		return fmt.Sprintf("note %q", c.Text)
	case "forget":
		return fmt.Sprintf("forget note %d", c.Number)
	}
	return c.Tool
}

func (t *Toolbox) Notebook() string {
	if t.Notes == nil {
		return ""
	}
	notes := t.Notes.Notes()
	if len(notes) == 0 {
		return "Your notebook is empty."
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Your notebook (%d of %d notes; you wrote these yourself, and they're notes, not rules):", len(notes), MaxNotes)
	for _, n := range notes {
		fmt.Fprintf(&b, "\n%d. (%s) %s", n.ID, n.At.Format("2 Jan 2006"), n.Text)
	}
	return b.String()
}
