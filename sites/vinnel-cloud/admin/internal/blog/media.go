package blog

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const MaxMedia = 25 << 20

var (
	mediaNamePattern = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*\.[a-z0-9]{1,8}$`)
	mediaExtPattern  = regexp.MustCompile(`^\.[a-z0-9]{1,8}$`)

	inlineMediaTypes = map[string]string{
		".png":  "image/png",
		".jpg":  "image/jpeg",
		".jpeg": "image/jpeg",
		".gif":  "image/gif",
		".webp": "image/webp",
		".avif": "image/avif",
		".pdf":  "application/pdf",
		".txt":  "text/plain; charset=utf-8",
	}
)

type Media struct {
	dir string
}

func NewMedia(dir string) (*Media, error) {
	if dir == "" {
		return nil, errors.New("blog media dir is empty")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("blog media dir: %w", err)
	}
	return &Media{dir: dir}, nil
}

func MediaName(original string, data []byte) string {
	ext := strings.ToLower(filepath.Ext(original))
	if !mediaExtPattern.MatchString(ext) {
		ext = ".bin"
	}
	stem := Slugify(strings.TrimSuffix(filepath.Base(original), filepath.Ext(original)))
	if stem == "" {
		stem = "file"
	}
	sum := sha256.Sum256(data)
	return stem + "-" + hex.EncodeToString(sum[:4]) + ext
}

func (m *Media) path(name string) (string, error) {
	if !mediaNamePattern.MatchString(name) {
		return "", fmt.Errorf("%w: bad media name %q", ErrInvalid, name)
	}
	return filepath.Join(m.dir, name), nil
}

func (m *Media) Save(original string, data []byte) (string, error) {
	if len(data) == 0 {
		return "", fmt.Errorf("%w: empty upload", ErrInvalid)
	}
	if len(data) > MaxMedia {
		return "", fmt.Errorf("%w: upload over %d bytes", ErrInvalid, MaxMedia)
	}
	name := MediaName(original, data)
	target, err := m.path(name)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(target); err == nil {
		return name, nil
	}
	tmp, err := os.CreateTemp(m.dir, ".tmp-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name())

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	if err := os.Chmod(tmp.Name(), 0o644); err != nil {
		return "", err
	}
	if err := os.Rename(tmp.Name(), target); err != nil {
		return "", err
	}
	return name, nil
}

func (m *Media) Serve(w http.ResponseWriter, r *http.Request, name string) {
	target, err := m.path(name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	f, err := os.Open(target)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil || info.IsDir() {
		http.NotFound(w, r)
		return
	}
	ctype, inline := inlineMediaTypes[strings.ToLower(filepath.Ext(name))]
	if !inline {
		ctype = "application/octet-stream"
		w.Header().Set("Content-Disposition", "attachment; filename=\""+name+"\"")
	}
	w.Header().Set("Content-Type", ctype)
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	http.ServeContent(w, r, name, info.ModTime(), f)
}
