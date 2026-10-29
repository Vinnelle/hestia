package tools

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode"
)

const (
	MaxNotes  = 30
	NoteChars = 200
)

type Note struct {
	ID   int       `json:"id"`
	Text string    `json:"text"`
	At   time.Time `json:"at"`
}

type Notebook struct {
	path  string
	mu    sync.Mutex
	notes []Note
	next  int
}

// A notebook that isn't JSON is set aside rather than failing the bot, so one
// bad file never keeps the bot out of the room.
func OpenNotebook(path string, logf func(format string, args ...any)) (*Notebook, error) {
	n := &Notebook{path: path, next: 1}
	if path == "" {
		return n, nil
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return n, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(data, &n.notes); err != nil {
		if err := os.Rename(path, path+".bad"); err != nil {
			return nil, err
		}
		logf("the notebook wasn't JSON, so it's now %s.bad and a new one starts", path)
		n.notes = nil
	}
	for _, note := range n.notes {
		n.next = max(n.next, note.ID+1)
	}
	return n, nil
}

func (n *Notebook) Add(text string, at time.Time) (string, error) {
	text = strings.Join(strings.FieldsFunc(text, func(r rune) bool {
		return unicode.IsSpace(r) || unicode.IsControl(r) || unicode.Is(unicode.Cf, r)
	}), " ")
	switch {
	case text == "":
		return "", errors.New("the note is empty")
	case len([]rune(text)) > NoteChars:
		return "", fmt.Errorf("the note is over %d characters", NoteChars)
	}
	n.mu.Lock()
	defer n.mu.Unlock()
	for _, note := range n.notes {
		if strings.EqualFold(note.Text, text) {
			return "", fmt.Errorf("that's already note %d", note.ID)
		}
	}
	if len(n.notes) >= MaxNotes {
		return "", fmt.Errorf("the notebook is full (%d notes): forget one first", MaxNotes)
	}
	note := Note{ID: n.next, Text: text, At: at.UTC().Truncate(time.Second)}
	notes := append(slices.Clip(n.notes), note)
	if err := n.save(notes); err != nil {
		return "", err
	}
	n.notes = notes
	n.next++
	return fmt.Sprintf("saved as note %d", note.ID), nil
}

func (n *Notebook) Forget(id int) (string, error) {
	n.mu.Lock()
	defer n.mu.Unlock()
	for i, note := range n.notes {
		if note.ID != id {
			continue
		}
		notes := append(append([]Note{}, n.notes[:i]...), n.notes[i+1:]...)
		if err := n.save(notes); err != nil {
			return "", err
		}
		n.notes = notes
		return fmt.Sprintf("crossed out note %d", id), nil
	}
	return "", fmt.Errorf("there's no note %d", id)
}

func (n *Notebook) Notes() []Note {
	n.mu.Lock()
	defer n.mu.Unlock()
	return append([]Note{}, n.notes...)
}

func (n *Notebook) save(notes []Note) error {
	if n.path == "" {
		return nil
	}
	data, err := json.MarshalIndent(notes, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(n.path), ".notes-*")
	if err != nil {
		return fmt.Errorf("saving the notebook: %w", err)
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(append(data, '\n')); err != nil {
		tmp.Close()
		return fmt.Errorf("saving the notebook: %w", err)
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return fmt.Errorf("saving the notebook: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("saving the notebook: %w", err)
	}
	if err := os.Rename(tmp.Name(), n.path); err != nil {
		return fmt.Errorf("saving the notebook: %w", err)
	}
	return nil
}
