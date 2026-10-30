package tools

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
)

func TestDraw(t *testing.T) {
	for _, pose := range Poses {
		for _, face := range Faces {
			lines, err := Draw(pose, face, "hi")
			if err != nil {
				t.Fatalf("%s, %s: %v", pose, face, err)
			}
			for _, line := range lines {
				if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), ":") || len(line) > 60 {
					t.Errorf("%s, %s drew a bad line %q", pose, face, line)
				}
			}
		}
	}
	got, _ := Draw("sit", "wink", "  LMR\x1b[31m    rawr\u202e!! ")
	if got[2] != `\  ^   -  /   < LMR [31m rawr !! >` || got[3] != ` \_  w  _/     __` {
		t.Errorf("sit, wink drew:\n%s", strings.Join(got, "\n"))
	}
	sign, _ := Draw("sign", "sus", "FED DETECTED")
	want := []string{
		" .----------------.",
		" |  FED DETECTED  |",
		" '----------------'",
		"     | /\\     /\\ |",
		"     |/  \\___/  \\|",
		"     |\\  o   O  /|",
		"      \\\\_  _  _//",
	}
	if strings.Join(sign, "\n") != strings.Join(want, "\n") {
		t.Errorf("the sign came out:\n%s", strings.Join(sign, "\n"))
	}
	if long := Caption(strings.Repeat("a", 40)); len(long) != CaptionChars {
		t.Errorf("a long caption kept %d characters", len(long))
	}
	for _, bad := range [][3]string{{"dance", "happy", ""}, {"sit", "angry", ""}, {"sign", "happy", "  "}} {
		if _, err := Draw(bad[0], bad[1], bad[2]); err == nil {
			t.Errorf("drew %q", bad)
		}
	}
}

const usage = "# Usage\n\nchat runs in the terminal.\n\n## Commands\n\n:new makes a private room with its own password.\n:verify NICK compares verify codes.\n\n" +
	"```sh\n# not a heading\nchat --session x\n```\n\n## Settings\n\nThe colour of your nick is a setting.\n"

func docsSite() pages {
	return pages{
		docsRaw + "v0.5.4/README.md":           page("text/plain", "# chat\n\nAn encrypted group chat.\n"),
		docsRaw + "v0.5.4/docs/README.md":      page("text/plain", "# Documentation\n\n- [Usage](usage.md): commands.\n- [Gone](gone.md)\n- [Security](../SECURITY.md)\n- [Escape](../../etc/passwd.md)\n"),
		docsRaw + "v0.5.4/docs/usage.md":       page("text/plain", usage),
		docsRaw + "v0.5.4/SECURITY.md":         page("text/plain", "# Security\n\nReport vulnerabilities by email.\n"),
		docsRaw + "v0.5.4/docs/does-not-exist": page("text/plain", ""),
	}
}

func TestDocs(t *testing.T) {
	d := &Docs{Reader: &Reader{HTTP: &http.Client{Transport: docsSite()}}}
	if _, err := d.Search(context.Background(), "verify"); err == nil {
		t.Error("searched before knowing chat's version")
	}
	n, err := d.Load(context.Background(), "v0.5.4")
	if err != nil {
		t.Fatal(err)
	}
	if n != 6 {
		t.Errorf("loaded %d sections; want 6", n)
	}
	got, err := d.Search(context.Background(), "How do I verify someone?")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(got, "chat's docs at v0.5.4, best matches first:\n\ndocs/usage.md, \"Commands\" <https://github.com/Vinnelle/chat/blob/v0.5.4/docs/usage.md>\n:new makes") {
		t.Errorf("verify found:\n%s", got)
	}
	got, _ = d.Search(context.Background(), "chat settings colours")
	if !strings.Contains(got, `"Settings"`) || strings.Contains(got, `"Commands"`) {
		t.Errorf("settings found:\n%s", got)
	}
	if got, _ := d.Search(context.Background(), "heading"); strings.Contains(got, `"not a heading"`) {
		t.Errorf("a comment in a code block became a heading:\n%s", got)
	}
	if got, _ := d.Search(context.Background(), "kubernetes"); got != `nothing in chat's docs (v0.5.4) mentions "kubernetes"` {
		t.Errorf("a miss gave %q", got)
	}
}

func TestDocsFailToLoad(t *testing.T) {
	d := &Docs{Reader: &Reader{HTTP: &http.Client{Transport: pages{}}}}
	if _, err := d.Load(context.Background(), "v9.9.9"); err == nil {
		t.Fatal("loaded docs that aren't there")
	}
	if _, err := d.Search(context.Background(), "verify"); err == nil || !strings.Contains(err.Error(), "couldn't load chat's docs") {
		t.Errorf("searching unloaded docs gave %v", err)
	}
}

func TestManual(t *testing.T) {
	man := "rsync(1) User Commands rsync(1)\n\nNAME\n       rsync - a fast, versatile file-copying tool\n\n" +
		"       --delete\n              delete extraneous files from dest dirs\n\n       --archive, -a\n              archive mode\n"
	r := &Reader{HTTP: &http.Client{Transport: pages{
		tldrRaw + "linux/rsync.md":           page("text/plain", "# rsync\n\n> Transfer files.\n> More information: <https://rsync.samba.org>.\n\n- Copy a file:\n\n`rsync {{path/to/src}} {{path/to/dest}}`\n"),
		manPages + "rsync.txt":               page("text/plain; charset=utf8", man),
		manPages + "sshd_config.5.txt":       page("text/plain; charset=utf8", "sshd_config(5)\n\nNAME\n       sshd_config - OpenSSH daemon configuration file\n"),
		tldrRaw + "common/docker-compose.md": page("text/plain", "# docker compose\n\n> Run containers.\n\n- Start:\n\n`docker compose up`\n"),
	}}}
	got, err := r.Manual(context.Background(), "rsync", "delete extraneous")
	if err != nil {
		t.Fatal(err)
	}
	want := "tldr rsync (tldr-pages, CC BY 4.0):\nTransfer files.\nMore information: <https://rsync.samba.org>.\n- Copy a file: rsync path/to/src path/to/dest\n\n" +
		"man page rsync <https://man.archlinux.org/man/rsync>:\n--delete\ndelete extraneous files from dest dirs"
	if got != want {
		t.Errorf("rsync gave:\n%s", got)
	}
	if got, err := r.Manual(context.Background(), "sshd_config(5)", ""); err != nil || !strings.Contains(got, "OpenSSH daemon configuration file") || strings.Contains(got, "tldr") {
		t.Errorf("sshd_config(5) gave %q, %v", got, err)
	}
	if got, err := r.Manual(context.Background(), "docker compose", ""); err != nil || !strings.HasPrefix(got, "tldr docker-compose") {
		t.Errorf("docker compose gave %q, %v", got, err)
	}
	if _, err := r.Manual(context.Background(), "nosuchthing", ""); err == nil || !strings.Contains(err.Error(), "no tldr page or manual page") {
		t.Errorf("a missing page gave %v", err)
	}
	for _, bad := range []string{"../etc/passwd", "a/b", "-rf", "rm; ls"} {
		if _, err := r.Manual(context.Background(), bad, ""); err == nil || !strings.Contains(err.Error(), "give the name") {
			t.Errorf("%q gave %v", bad, err)
		}
	}
}

func TestToolboxOffersLookupsAndDrawing(t *testing.T) {
	box := &Toolbox{Read: &Reader{HTTP: &http.Client{Transport: pages{}}}, Docs: &Docs{}}
	s := string(box.Schema())
	var schema map[string]any
	if err := json.Unmarshal([]byte(s), &schema); err != nil {
		t.Fatalf("schema isn't JSON: %v\n%s", err, s)
	}
	for _, want := range []string{`"const":"docs"`, `"const":"manual"`, `"const":"draw"`, `"pose":{"enum":["sit","wave","head","sign"]}`, `"caption":{"type":"string","minLength":0,"maxLength":24}`} {
		if !strings.Contains(s, want) {
			t.Errorf("schema lacks %s", want)
		}
	}
	results := box.Run(context.Background(), []Call{{Tool: "draw", Pose: "head", Face: "uwu"}})
	if r := results[0]; r.Err != nil || !strings.Contains(r.Text, `\  u   u  /`) || strings.Count(r.Text, "\n") != 4 {
		t.Errorf("draw gave %q, %v", r.Text, r.Err)
	}
	if got := (Call{Tool: "draw", Pose: "sign", Face: "sus", Caption: "fed"}).String(); got != `draw sign, sus, "fed"` {
		t.Errorf("String = %s", got)
	}
	if got := (&Toolbox{}).Describe(); strings.Contains(got, "docs (") || strings.Contains(got, "manual (") || !strings.Contains(got, "draw (pose, face, caption)") {
		t.Errorf("a toolbox without Tor describes:\n%s", got)
	}
}

func TestAbilities(t *testing.T) {
	notes, _ := OpenNotebook("", nil)
	reader := &Reader{HTTP: &http.Client{Transport: docsSite()}}
	box := &Toolbox{Read: reader, Docs: &Docs{Reader: reader}, Notes: notes}
	if !strings.Contains(string(box.Schema()), `"about":{"enum":["all","read","docs","manual","time","calculate","draw","note","forget","abilities"]}`) {
		t.Errorf("abilities can't be asked about every tool: %s", box.Schema())
	}
	if got, _ := box.abilities("docs"); !strings.HasSuffix(got, "Now: chat's docs haven't loaded yet.") {
		t.Errorf("before loading, docs reads %q", got)
	}
	box.Docs.Load(context.Background(), "v0.5.4")
	all, err := box.abilities("all")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"- read (url, find): Opens a public http or https page over Tor",
		"Now: chat v0.5.4's docs are loaded, 6 sections from 4 pages.",
		"- manual (page, find): Fetches, over Tor, the tldr-pages examples",
		"Poses: sit, wave, head, sign (sign holds up a sign with the caption on it). Faces: happy, uwu, excited, curious, sleepy, wink, sus.",
		"- note (text): Writes a note in your notebook, which lasts across restarts: up to 30 notes of 200 characters, numbered for good. You see the whole notebook every turn. Now: 0 of 30 notes used.",
		"- abilities (about): Tells you what your tools can do",
	} {
		if !strings.Contains(all, want) {
			t.Errorf("abilities lacks %q:\n%s", want, all)
		}
	}
	if strings.Contains(all, "- search") {
		t.Error("abilities describes search, which this toolbox doesn't have")
	}
	one, _ := box.abilities("draw")
	if strings.Count(one, "\n") != 0 || !strings.HasPrefix(one, "- draw (pose, face, caption): Draws you") {
		t.Errorf("abilities of draw = %q", one)
	}
	if _, err := box.abilities("teleport"); err == nil {
		t.Error("described a tool that doesn't exist")
	}
	if got := box.Run(context.Background(), []Call{{Tool: "abilities", About: "time"}})[0]; got.Err != nil || !strings.HasPrefix(got.Text, "- time (zone): The current date") || got.Call.String() != "abilities of time" {
		t.Errorf("running abilities gave %q, %v", got.Text, got.Err)
	}
}
