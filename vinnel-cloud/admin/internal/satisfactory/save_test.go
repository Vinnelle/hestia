package satisfactory

import (
	"bytes"
	"encoding/binary"
	"testing"
	"time"
	"unicode/utf16"
)

func writeU32(buf *bytes.Buffer, v uint32) { binary.Write(buf, binary.LittleEndian, v) }
func writeU64(buf *bytes.Buffer, v uint64) { binary.Write(buf, binary.LittleEndian, v) }
func writeI8(buf *bytes.Buffer, v int8)    { binary.Write(buf, binary.LittleEndian, v) }

func writeAsciiString(buf *bytes.Buffer, s string) {
	writeU32(buf, uint32(len(s)+1))
	buf.WriteString(s)
	buf.WriteByte(0)
}

func writeUTF16String(buf *bytes.Buffer, s string) {
	units := utf16.Encode([]rune(s))
	writeU32(buf, uint32(int32(-(len(units) + 1))))
	for _, u := range units {
		binary.Write(buf, binary.LittleEndian, u)
	}
	binary.Write(buf, binary.LittleEndian, uint16(0))
}

func synthSaveHeader(saveVersion uint32) []byte {
	var buf bytes.Buffer
	writeU32(&buf, 14)
	writeU32(&buf, saveVersion)
	writeU32(&buf, 999999)
	if saveVersion >= 14 {
		writeAsciiString(&buf, "save1")
	}
	writeUTF16String(&buf, "Persistent_Level")
	writeAsciiString(&buf, "")
	writeAsciiString(&buf, "My Factory")
	writeU32(&buf, 12345)
	writeU64(&buf, dotnetEpochToUnixTicks+10_000_000_000)
	writeI8(&buf, 1)
	if saveVersion >= 7 {
		writeU32(&buf, 0)
	}
	if saveVersion >= 8 {
		writeAsciiString(&buf, "")
	}
	writeU32(&buf, 0)
	if saveVersion >= 10 {
		writeAsciiString(&buf, "id-123")
	}
	if saveVersion >= 13 {
		writeU32(&buf, 1)
		writeU32(&buf, 1)
		writeU64(&buf, 0)
		writeU64(&buf, 0)
		writeU32(&buf, 1)
	}
	return buf.Bytes()
}

func TestParseSaveHeader(t *testing.T) {
	h, err := parseSaveHeader(bytes.NewReader(synthSaveHeader(53)))
	if err != nil {
		t.Fatalf("parseSaveHeader: %v", err)
	}
	if h.SaveVersion != 53 {
		t.Errorf("SaveVersion = %d, want 53", h.SaveVersion)
	}
	if h.MapName != "Persistent_Level" {
		t.Errorf("MapName = %q, want %q", h.MapName, "Persistent_Level")
	}
	if h.SessionName != "My Factory" {
		t.Errorf("SessionName = %q, want %q", h.SessionName, "My Factory")
	}
	if h.PlayDurationSecs != 12345 {
		t.Errorf("PlayDurationSecs = %d, want 12345", h.PlayDurationSecs)
	}
	if !h.IsCreativeModeOn {
		t.Errorf("IsCreativeModeOn = false, want true")
	}
	wantSavedAt := time.Unix(1000, 0).UTC()
	if !h.SavedAt.Equal(wantSavedAt) {
		t.Errorf("SavedAt = %v, want %v", h.SavedAt, wantSavedAt)
	}
}

func TestParseSaveHeaderRejectsUnknownType(t *testing.T) {
	var buf bytes.Buffer
	writeU32(&buf, 999)
	if _, err := parseSaveHeader(&buf); err == nil {
		t.Fatal("expected error for unsupported save header type")
	}
}

func TestParseSaveHeaderTruncated(t *testing.T) {
	full := synthSaveHeader(53)
	if _, err := parseSaveHeader(bytes.NewReader(full[:len(full)-10])); err == nil {
		t.Fatal("expected error on truncated input")
	}
}
