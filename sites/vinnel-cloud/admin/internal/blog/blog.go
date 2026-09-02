package blog

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode"
)

const (
	MaxTitle = 200
	MaxBody  = 200 << 10
	MaxSlug  = 80
)

var (
	ErrNotFound = errors.New("post not found")
	ErrInvalid  = errors.New("invalid post")

	slugPattern = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
	datePattern = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
)

type Post struct {
	Slug      string    `json:"slug"`
	Title     string    `json:"title"`
	Date      string    `json:"date"`
	Body      string    `json:"body"`
	Draft     bool      `json:"draft"`
	UpdatedAt time.Time `json:"updatedAt"`
}

func ValidSlug(s string) bool {
	return len(s) > 0 && len(s) <= MaxSlug && slugPattern.MatchString(s)
}

func Slugify(title string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(title) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			dash = false
		case unicode.IsSpace(r), r == '-', r == '_', r == '/':
			if !dash && b.Len() > 0 {
				b.WriteByte('-')
				dash = true
			}
		}
	}
	s := strings.Trim(b.String(), "-")
	if len(s) > MaxSlug {
		s = strings.Trim(s[:MaxSlug], "-")
	}
	return s
}

func (p *Post) Validate() error {
	if !ValidSlug(p.Slug) {
		return fmt.Errorf("%w: slug must match %s and be 1-%d chars", ErrInvalid, slugPattern, MaxSlug)
	}
	title := strings.TrimSpace(p.Title)
	if title == "" {
		return fmt.Errorf("%w: title is required", ErrInvalid)
	}
	if len(title) > MaxTitle {
		return fmt.Errorf("%w: title over %d chars", ErrInvalid, MaxTitle)
	}
	if strings.ContainsAny(title, "\r\n") {
		return fmt.Errorf("%w: title must be a single line", ErrInvalid)
	}
	if !datePattern.MatchString(p.Date) {
		return fmt.Errorf("%w: date must be YYYY-MM-DD", ErrInvalid)
	}
	if _, err := time.Parse("2006-01-02", p.Date); err != nil {
		return fmt.Errorf("%w: date is not a real date", ErrInvalid)
	}
	if len(p.Body) > MaxBody {
		return fmt.Errorf("%w: body over %d bytes", ErrInvalid, MaxBody)
	}
	p.Title = title
	return nil
}

func (p *Post) Marshal() []byte {
	draft := "false"
	if p.Draft {
		draft = "true"
	}
	var b strings.Builder
	b.WriteString("---\n")
	b.WriteString("title: " + p.Title + "\n")
	b.WriteString("date: " + p.Date + "\n")
	b.WriteString("draft: " + draft + "\n")
	b.WriteString("---\n\n")
	b.WriteString(strings.ReplaceAll(p.Body, "\r\n", "\n"))
	if !strings.HasSuffix(b.String(), "\n") {
		b.WriteString("\n")
	}
	return []byte(b.String())
}

func Unmarshal(slug string, data []byte) (*Post, error) {
	text := strings.ReplaceAll(string(data), "\r\n", "\n")
	if !strings.HasPrefix(text, "---\n") {
		return nil, fmt.Errorf("%w: missing front matter", ErrInvalid)
	}
	rest := text[len("---\n"):]
	end := strings.Index(rest, "\n---\n")
	if end < 0 {
		return nil, fmt.Errorf("%w: unterminated front matter", ErrInvalid)
	}
	p := &Post{Slug: slug}
	for _, line := range strings.Split(rest[:end], "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		value = strings.TrimSpace(value)
		switch strings.TrimSpace(key) {
		case "title":
			p.Title = value
		case "date":
			p.Date = value
		case "draft":
			p.Draft = value == "true"
		}
	}
	p.Body = strings.TrimLeft(rest[end+len("\n---\n"):], "\n")
	return p, nil
}

type Store struct {
	mu   sync.RWMutex
	root string
}

func NewStore(root string) (*Store, error) {
	if root == "" {
		return nil, errors.New("blog store root is empty")
	}
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, fmt.Errorf("blog store root: %w", err)
	}
	return &Store{root: root}, nil
}

func (s *Store) path(slug string) (string, error) {
	if !ValidSlug(slug) {
		return "", fmt.Errorf("%w: bad slug %q", ErrInvalid, slug)
	}
	return filepath.Join(s.root, slug+".md"), nil
}

func (s *Store) All() ([]*Post, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	entries, err := os.ReadDir(s.root)
	if err != nil {
		return nil, err
	}
	posts := make([]*Post, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".md") {
			continue
		}
		slug := strings.TrimSuffix(e.Name(), ".md")
		if !ValidSlug(slug) {
			continue
		}
		p, err := s.read(slug)
		if err != nil {
			continue
		}
		posts = append(posts, p)
	}
	sort.Slice(posts, func(i, j int) bool {
		if posts[i].Date != posts[j].Date {
			return posts[i].Date > posts[j].Date
		}
		return posts[i].Slug < posts[j].Slug
	})
	return posts, nil
}

func (s *Store) List() ([]*Post, error) {
	posts, err := s.All()
	if err != nil {
		return nil, err
	}
	for _, p := range posts {
		p.Body = ""
	}
	return posts, nil
}

func (s *Store) read(slug string) (*Post, error) {
	name, err := s.path(slug)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(name)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	p, err := Unmarshal(slug, data)
	if err != nil {
		return nil, err
	}
	if info, err := os.Stat(name); err == nil {
		p.UpdatedAt = info.ModTime().UTC()
	}
	return p, nil
}

func (s *Store) Get(slug string) (*Post, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.read(slug)
}

func (s *Store) Save(p *Post) error {
	if err := p.Validate(); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()

	name, err := s.path(p.Slug)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(s.root, ".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())

	if _, err := tmp.Write(p.Marshal()); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), name)
}

func (s *Store) Delete(slug string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	name, err := s.path(slug)
	if err != nil {
		return err
	}
	if err := os.Remove(name); err != nil {
		if os.IsNotExist(err) {
			return ErrNotFound
		}
		return err
	}
	return nil
}

func (s *Store) Exists(slug string) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	name, err := s.path(slug)
	if err != nil {
		return false
	}
	_, err = os.Stat(name)
	return err == nil
}
