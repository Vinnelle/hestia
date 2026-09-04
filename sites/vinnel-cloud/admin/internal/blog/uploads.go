package blog

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

const UploadChunkSize = 16 << 20

var uploadIDPattern = regexp.MustCompile(`^[a-f0-9]{32}$`)

type UploadStatus struct {
	ID          string  `json:"id"`
	Size        int64   `json:"size"`
	ChunkSize   int64   `json:"chunkSize"`
	TotalChunks int64   `json:"totalChunks"`
	Received    []int64 `json:"received"`
	Complete    bool    `json:"complete"`
	Name        string  `json:"name,omitempty"`
}

type uploadMeta struct {
	Original  string `json:"original"`
	Size      int64  `json:"size"`
	ChunkSize int64  `json:"chunkSize"`
}

type uploadResult struct {
	Name string `json:"name"`
}

func (m *Media) StartUpload(original string, size int64) (*UploadStatus, error) {
	return m.StartUploadWithChunkSize(original, size, UploadChunkSize)
}

func (m *Media) StartUploadWithChunkSize(original string, size, chunkSize int64) (*UploadStatus, error) {
	if strings.TrimSpace(original) == "" {
		return nil, fmt.Errorf("%w: file name is required", ErrInvalid)
	}
	if size <= 0 {
		return nil, fmt.Errorf("%w: empty upload", ErrInvalid)
	}
	if chunkSize <= 0 {
		return nil, fmt.Errorf("%w: invalid chunk size", ErrInvalid)
	}

	root := filepath.Join(m.dir, ".uploads")
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	for {
		idBytes := make([]byte, 16)
		if _, err := rand.Read(idBytes); err != nil {
			return nil, err
		}
		id := hex.EncodeToString(idBytes)
		dir := filepath.Join(root, id)
		if err := os.Mkdir(dir, 0o755); err != nil {
			if errors.Is(err, os.ErrExist) {
				continue
			}
			return nil, err
		}
		meta := uploadMeta{Original: original, Size: size, ChunkSize: chunkSize}
		if err := writeUploadJSON(filepath.Join(dir, "meta.json"), meta); err != nil {
			os.RemoveAll(dir)
			return nil, err
		}
		return &UploadStatus{
			ID:          id,
			Size:        meta.Size,
			ChunkSize:   meta.ChunkSize,
			TotalChunks: uploadTotalChunks(meta.Size, meta.ChunkSize),
			Received:    []int64{},
		}, nil
	}
}

func uploadTotalChunks(size, chunkSize int64) int64 {
	chunks := size / chunkSize
	if size%chunkSize != 0 {
		chunks++
	}
	return chunks
}

func writeUploadJSON(name string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(name), ".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	if _, err := tmp.Write(data); err != nil {
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), name)
}

func (m *Media) readUpload(id string) (string, uploadMeta, error) {
	if !uploadIDPattern.MatchString(id) {
		return "", uploadMeta{}, fmt.Errorf("%w: bad upload id %q", ErrInvalid, id)
	}
	dir := filepath.Join(m.dir, ".uploads", id)
	data, err := os.ReadFile(filepath.Join(dir, "meta.json"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", uploadMeta{}, ErrNotFound
		}
		return "", uploadMeta{}, err
	}
	var meta uploadMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return "", uploadMeta{}, fmt.Errorf("%w: malformed upload metadata", ErrInvalid)
	}
	if strings.TrimSpace(meta.Original) == "" || meta.Size <= 0 || meta.ChunkSize <= 0 {
		return "", uploadMeta{}, fmt.Errorf("%w: malformed upload metadata", ErrInvalid)
	}
	return dir, meta, nil
}

func readUploadResult(dir string) (string, bool, error) {
	data, err := os.ReadFile(filepath.Join(dir, "result.json"))
	if errors.Is(err, os.ErrNotExist) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	var result uploadResult
	if err := json.Unmarshal(data, &result); err != nil || !mediaNamePattern.MatchString(result.Name) {
		return "", false, fmt.Errorf("%w: malformed upload result", ErrInvalid)
	}
	return result.Name, true, nil
}

func (m *Media) UploadStatus(id string) (*UploadStatus, error) {
	dir, meta, err := m.readUpload(id)
	if err != nil {
		return nil, err
	}
	name, complete, err := readUploadResult(dir)
	if err != nil {
		return nil, err
	}
	status := &UploadStatus{
		ID:          id,
		Size:        meta.Size,
		ChunkSize:   meta.ChunkSize,
		TotalChunks: uploadTotalChunks(meta.Size, meta.ChunkSize),
		Received:    []int64{},
		Complete:    complete,
		Name:        name,
	}
	if complete {
		return status, nil
	}
	status.Received, err = m.receivedChunks(dir, meta)
	return status, err
}

func uploadChunkPath(dir string, index int64) string {
	return filepath.Join(dir, "chunk-"+strconv.FormatInt(index, 10)+".part")
}

func uploadChunkLength(meta uploadMeta, index int64) (int64, error) {
	total := uploadTotalChunks(meta.Size, meta.ChunkSize)
	if index < 0 || index >= total {
		return 0, fmt.Errorf("%w: chunk index %d is outside the upload", ErrInvalid, index)
	}
	remaining := meta.Size - index*meta.ChunkSize
	if remaining > meta.ChunkSize {
		return meta.ChunkSize, nil
	}
	return remaining, nil
}

func (m *Media) receivedChunks(dir string, meta uploadMeta) ([]int64, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	received := make([]int64, 0)
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasPrefix(name, "chunk-") || !strings.HasSuffix(name, ".part") {
			continue
		}
		index, err := strconv.ParseInt(strings.TrimSuffix(strings.TrimPrefix(name, "chunk-"), ".part"), 10, 64)
		if err != nil {
			continue
		}
		length, err := uploadChunkLength(meta, index)
		if err != nil {
			continue
		}
		info, err := entry.Info()
		if err == nil && info.Size() == length {
			received = append(received, index)
		}
	}
	sort.Slice(received, func(i, j int) bool { return received[i] < received[j] })
	return received, nil
}

func (m *Media) UploadChunk(id string, index int64, src io.Reader) error {
	if src == nil {
		return fmt.Errorf("%w: empty chunk", ErrInvalid)
	}
	dir, meta, err := m.readUpload(id)
	if err != nil {
		return err
	}
	if _, complete, err := readUploadResult(dir); err != nil {
		return err
	} else if complete {
		return nil
	}
	length, err := uploadChunkLength(meta, index)
	if err != nil {
		return err
	}
	target := uploadChunkPath(dir, index)
	if info, err := os.Stat(target); err == nil {
		if info.Size() == length {
			return nil
		}
		return fmt.Errorf("%w: chunk %d has the wrong size", ErrInvalid, index)
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}

	tmp, err := os.CreateTemp(dir, ".chunk-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	n, err := io.CopyN(tmp, src, length+1)
	if err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	if n != length {
		return fmt.Errorf("%w: chunk %d has %d bytes, want %d", ErrInvalid, index, n, length)
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), target)
}

func (m *Media) CompleteUpload(id string) (string, error) {
	dir, meta, err := m.readUpload(id)
	if err != nil {
		return "", err
	}
	if name, complete, err := readUploadResult(dir); err != nil {
		return "", err
	} else if complete {
		m.removeUploadChunks(dir, meta)
		return name, nil
	}

	lock, err := os.OpenFile(filepath.Join(dir, "complete.lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return "", err
	}
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		lock.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return "", fmt.Errorf("%w: completion already in progress", ErrInvalid)
		}
		return "", err
	}
	defer lock.Close()
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)

	if name, complete, err := readUploadResult(dir); err != nil {
		return "", err
	} else if complete {
		m.removeUploadChunks(dir, meta)
		return name, nil
	}
	received, err := m.receivedChunks(dir, meta)
	if err != nil {
		return "", err
	}
	if int64(len(received)) != uploadTotalChunks(meta.Size, meta.ChunkSize) {
		return "", fmt.Errorf("%w: upload is missing chunks", ErrInvalid)
	}

	tmp, err := os.CreateTemp(m.dir, ".tmp-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	hash := sha256.New()
	for index := int64(0); index < uploadTotalChunks(meta.Size, meta.ChunkSize); index++ {
		length, err := uploadChunkLength(meta, index)
		if err != nil {
			return "", err
		}
		part, err := os.Open(uploadChunkPath(dir, index))
		if err != nil {
			return "", err
		}
		n, copyErr := io.Copy(io.MultiWriter(tmp, hash), part)
		closeErr := part.Close()
		if copyErr != nil {
			return "", copyErr
		}
		if closeErr != nil {
			return "", closeErr
		}
		if n != length {
			return "", fmt.Errorf("%w: chunk %d changed during completion", ErrInvalid, index)
		}
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	var sum [sha256.Size]byte
	copy(sum[:], hash.Sum(nil))
	name := mediaName(meta.Original, sum)
	target, err := m.path(name)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(target); err != nil {
		if err := os.Chmod(tmp.Name(), 0o644); err != nil {
			return "", err
		}
		if err := os.Rename(tmp.Name(), target); err != nil {
			return "", err
		}
	}
	if err := writeUploadJSON(filepath.Join(dir, "result.json"), uploadResult{Name: name}); err != nil {
		return "", err
	}
	m.removeUploadChunks(dir, meta)
	return name, nil
}

func (m *Media) removeUploadChunks(dir string, meta uploadMeta) {
	for index := int64(0); index < uploadTotalChunks(meta.Size, meta.ChunkSize); index++ {
		os.Remove(uploadChunkPath(dir, index))
	}
}
