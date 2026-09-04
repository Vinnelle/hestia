package blog

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

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
	return mediaName(original, sha256.Sum256(data))
}

func mediaName(original string, sum [sha256.Size]byte) string {
	ext := strings.ToLower(filepath.Ext(original))
	if !mediaExtPattern.MatchString(ext) {
		ext = ".bin"
	}
	stem := Slugify(strings.TrimSuffix(filepath.Base(original), filepath.Ext(original)))
	if stem == "" {
		stem = "file"
	}
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
	return m.SaveReader(original, bytes.NewReader(data))
}

func (m *Media) SaveReader(original string, src io.Reader) (string, error) {
	if src == nil {
		return "", fmt.Errorf("%w: empty upload", ErrInvalid)
	}
	tmp, err := os.CreateTemp(m.dir, ".tmp-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()

	hash := sha256.New()
	n, err := io.Copy(io.MultiWriter(tmp, hash), src)
	if err != nil {
		return "", err
	}
	if n == 0 {
		return "", fmt.Errorf("%w: empty upload", ErrInvalid)
	}

	var sum [sha256.Size]byte
	copy(sum[:], hash.Sum(nil))
	name := mediaName(original, sum)
	target, err := m.path(name)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(target); err == nil {
		return name, nil
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
