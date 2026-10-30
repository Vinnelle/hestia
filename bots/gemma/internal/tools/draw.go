package tools

import (
	"errors"
	"fmt"
	"strings"
)

const CaptionChars = 24

var (
	Poses = []string{"sit", "wave", "head", "sign"}
	Faces = []string{"happy", "uwu", "excited", "curious", "sleepy", "wink", "sus"}
)

var faces = map[string][3]string{
	"happy":   {"^", "w", "^"},
	"uwu":     {"u", "w", "u"},
	"excited": {">", "w", "<"},
	"curious": {"o", "w", "o"},
	"sleepy":  {"-", "w", "-"},
	"wink":    {"^", "w", "-"},
	"sus":     {"o", "_", "O"},
}

var poses = map[string][]string{
	"sit": {
		` /\     /\`,
		`/  \___/  \`,
		`\  L   R  /`,
		` \_  M  _/     __`,
		"  /`---'\\    /  /",
		` |  | |  |  /  /`,
		` (__|_|__)-'--'`,
	},
	"wave": {
		` /\     /\`,
		`/  \___/  \     _`,
		`\  L   R  /    | |`,
		` \_  M  _/    _/ /`,
		"  /`---'\\___/  /",
		` |  | |   ___/`,
		` (__|_|__)`,
	},
	"head": {
		` /\     /\`,
		`/  \___/  \`,
		`\  L   R  /`,
		` \_  M  _/`,
		"   `---'",
	},
	"sign": {
		`| /\     /\ |`,
		`|/  \___/  \|`,
		`|\  L   R  /|`,
		` \\_  M  _//`,
	},
}

const eyeLine = 2

func Draw(pose, face, caption string) ([]string, error) {
	art, ok := poses[pose]
	if !ok {
		return nil, fmt.Errorf("pose is one of %s", strings.Join(Poses, ", "))
	}
	f, ok := faces[face]
	if !ok {
		return nil, fmt.Errorf("face is one of %s", strings.Join(Faces, ", "))
	}
	caption = Caption(caption)
	var lines []string
	pad := ""
	if pose == "sign" {
		if caption == "" {
			return nil, errors.New("a sign needs a caption to hold up")
		}
		width := max(len(caption), 10) + 4
		lines = append(lines,
			" ."+strings.Repeat("-", width)+".",
			" |  "+caption+strings.Repeat(" ", width-2-len(caption))+"|",
			" '"+strings.Repeat("-", width)+"'")
		pad = strings.Repeat(" ", (width-10)/2+2)
	}
	for i, line := range art {
		line = pad + strings.NewReplacer("L", f[0], "M", f[1], "R", f[2]).Replace(line)
		if i == eyeLine && pose != "sign" && caption != "" {
			line += "   < " + caption + " >"
		}
		lines = append(lines, line)
	}
	return lines, nil
}

func Caption(s string) string {
	s = strings.Map(func(r rune) rune {
		if r < ' ' || r > '~' {
			return ' '
		}
		return r
	}, s)
	s = strings.Join(strings.Fields(s), " ")
	if len(s) > CaptionChars {
		s = strings.TrimSpace(s[:CaptionChars])
	}
	return s
}
