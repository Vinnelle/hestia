package bot

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const historyLabel = "gemma history v1"

type History struct {
	path string
	aead cipher.AEAD
}

type kept struct {
	Saved   time.Time         `json:"saved"`
	Turns   []keptTurn        `json:"turns"`
	Aliases map[string]string `json:"aliases,omitempty"`
	Counted int               `json:"counted,omitempty"`
}

type keptTurn struct {
	Role    string `json:"role"`
	Text    string `json:"text,omitempty"`
	Nick    string `json:"nick,omitempty"`
	From    string `json:"from,omitempty"`
	Key     string `json:"key,omitempty"`
	Target  string `json:"target,omitempty"`
	About   bool   `json:"about,omitempty"`
	Mention bool   `json:"mention,omitempty"`
	Join    bool   `json:"join,omitempty"`
}

func OpenHistory(path string, key []byte) (*History, error) {
	if len(key) != 32 {
		return nil, errors.New("the history key must be 32 bytes")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &History{path: path, aead: aead}, nil
}

func (h *History) load() (*kept, error) {
	data, err := os.ReadFile(h.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var k kept
	n := h.aead.NonceSize()
	if len(data) >= n {
		var plain []byte
		if plain, err = h.aead.Open(nil, data[:n], data[n:], []byte(historyLabel)); err == nil {
			err = json.Unmarshal(plain, &k)
		}
	}
	if len(data) < n || err != nil {
		if err := os.Rename(h.path, h.path+".bad"); err != nil {
			return nil, err
		}
		return nil, fmt.Errorf("it couldn't be opened, so it's now %s.bad and a new one starts", h.path)
	}
	return &k, nil
}

func (h *History) save(k *kept) error {
	plain, err := json.Marshal(k)
	if err != nil {
		return err
	}
	nonce := make([]byte, h.aead.NonceSize())
	rand.Read(nonce)
	sealed := h.aead.Seal(nonce, nonce, plain, []byte(historyLabel))
	tmp, err := os.CreateTemp(filepath.Dir(h.path), ".history-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(sealed); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), h.path)
}
