package tools

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	name  string
	args  []arg
	about string
	run   func(ctx context.Context, c Call) (string, error)
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
		list = append(list, tool{"search", []arg{text("query", 1, maxQuery)},
			"search (query): search the web. You get titles, links and snippets; read a result when its snippet isn't enough.",
			func(ctx context.Context, c Call) (string, error) { return t.Search.Search(ctx, c.Query) }})
	}
	if t.Read != nil {
		list = append(list, tool{"read", []arg{text("url", 1, maxURL), text("find", 0, 100)},
			"read (url, find): open a web page and read its text. find is a few words to look for on a long page, or empty for its start.",
			func(ctx context.Context, c Call) (string, error) { return t.Read.Read(ctx, c.URL, c.Find) }})
	}
	if t.Docs != nil {
		list = append(list, tool{"docs", []arg{text("query", 1, maxQuery)},
			"docs (query): search chat's own documentation, at the version you run, for a command, setting, option or how something works. You get the best-matching sections and a link to each.",
			func(ctx context.Context, c Call) (string, error) { return t.Docs.Search(ctx, c.Query) }})
	}
	if t.Read != nil {
		list = append(list, tool{"manual", []arg{text("page", 1, maxPageName), text("find", 0, 100)},
			"manual (page, find): the tldr examples and the manual page for a Linux command, config file or function, like rsync, sshd_config or systemd.service. find is a few words to look for in the manual, such as an option, or empty for its start.",
			func(ctx context.Context, c Call) (string, error) { return t.Read.Manual(ctx, c.Page, c.Find) }})
	}
	list = append(list,
		tool{"time", []arg{text("zone", 0, maxZone)},
			"time (zone): the current date and time. zone is a time zone name like Europe/London or America/New_York, or empty for UTC.",
			func(ctx context.Context, c Call) (string, error) { return t.time(c.Zone) }},
		tool{"calculate", []arg{text("expression", 1, maxExpression)},
			"calculate (expression): exact arithmetic with + - * / % ^, parentheses, ! for factorials, pi, e, and sqrt, cbrt, abs, ln, log10, log2, exp, sin, cos, tan, asin, acos, atan, floor, ceil, round, min and max.",
			func(ctx context.Context, c Call) (string, error) { return Calculate(c.Expression) }},
		tool{"draw", []arg{choice("pose", Poses), choice("face", Faces), text("caption", 0, CaptionChars)},
			"draw (pose, face, caption): draw yourself as a fox in ASCII art, which goes up on its own lines right after your reply. pose sign holds up a sign with the caption on it; in the others the caption is a few words you say, or empty.",
			func(ctx context.Context, c Call) (string, error) {
				lines, err := Draw(c.Pose, c.Face, c.Caption)
				return strings.Join(lines, "\n"), err
			}})
	if t.Notes != nil {
		list = append(list,
			tool{"note", []arg{text("text", 1, NoteChars)},
				fmt.Sprintf("note (text): write a note of up to %d characters in your notebook.", NoteChars),
				func(ctx context.Context, c Call) (string, error) { return t.Notes.Add(c.Text, t.now()) }},
			tool{"forget", []arg{{"number", `{"type":"integer","minimum":1}`}},
				"forget (number): cross out a note in your notebook by its number.",
				func(ctx context.Context, c Call) (string, error) { return t.Notes.Forget(c.Number) }})
	}
	return list
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

func (t *Toolbox) Schema() json.RawMessage {
	var b strings.Builder
	for i, tl := range t.list() {
		if i > 0 {
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
