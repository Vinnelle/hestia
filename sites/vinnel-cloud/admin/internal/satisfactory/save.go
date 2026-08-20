// Decoder for the plain (uncompressed) header at the start of a Satisfactory
// .sav file. Field order and save-version gating come from the format itself,
// not from any game API — see CLAUDE.md for provenance.
package satisfactory

import (
	"encoding/binary"
	"fmt"
	"io"
	"time"
	"unicode/utf16"
)

type saveHeader struct {
	FileName         string    `json:"fileName"`
	SaveVersion      uint32    `json:"saveVersion"`
	BuildVersion     uint32    `json:"buildVersion"`
	MapName          string    `json:"mapName"`
	SessionName      string    `json:"sessionName"`
	PlayDurationSecs uint32    `json:"playDurationSeconds"`
	SavedAt          time.Time `json:"savedAt"`
	IsCreativeModeOn bool      `json:"isCreativeModeEnabled"`
}

const dotnetEpochToUnixTicks = 621355968000000000

const maxSaveStringBytes = 1 << 20

type byteReader struct {
	r   io.Reader
	err error
}

func (b *byteReader) read(buf []byte) {
	if b.err != nil {
		return
	}
	_, b.err = io.ReadFull(b.r, buf)
}

func (b *byteReader) uint8() uint8 {
	var buf [1]byte
	b.read(buf[:])
	return buf[0]
}

func (b *byteReader) int8() int8 { return int8(b.uint8()) }

func (b *byteReader) uint32() uint32 {
	var buf [4]byte
	b.read(buf[:])
	return binary.LittleEndian.Uint32(buf[:])
}

func (b *byteReader) int32() int32 { return int32(b.uint32()) }

func (b *byteReader) uint64() uint64 {
	var buf [8]byte
	b.read(buf[:])
	return binary.LittleEndian.Uint64(buf[:])
}

func (b *byteReader) string() string {
	n := b.int32()
	if b.err != nil || n == 0 {
		return ""
	}
	if n > 0 {
		if n > maxSaveStringBytes {
			b.err = fmt.Errorf("string length %d exceeds sanity limit", n)
			return ""
		}
		buf := make([]byte, n)
		b.read(buf)
		if b.err != nil || n == 0 {
			return ""
		}
		return string(buf[:n-1])
	}
	count := int(-n)
	if count*2 > maxSaveStringBytes {
		b.err = fmt.Errorf("string length %d exceeds sanity limit", count)
		return ""
	}
	buf := make([]byte, count*2)
	b.read(buf)
	if b.err != nil || count <= 1 {
		return ""
	}
	units := make([]uint16, count-1)
	for i := range units {
		units[i] = binary.LittleEndian.Uint16(buf[i*2:])
	}
	return string(utf16.Decode(units))
}

func parseSaveHeader(r io.Reader) (saveHeader, error) {
	var h saveHeader
	b := &byteReader{r: r}

	saveHeaderType := b.uint32()
	if b.err == nil && saveHeaderType != 13 && saveHeaderType != 14 {
		return h, fmt.Errorf("unsupported save header type %d", saveHeaderType)
	}
	saveVersion := b.uint32()
	h.SaveVersion = saveVersion
	h.BuildVersion = b.uint32()
	if saveVersion >= 14 {
		b.string()
	}
	h.MapName = b.string()
	b.string()
	h.SessionName = b.string()
	h.PlayDurationSecs = b.uint32()
	ticks := b.uint64()
	if b.err == nil {
		h.SavedAt = time.Unix(0, (int64(ticks)-dotnetEpochToUnixTicks)*100).UTC()
	}
	b.int8()
	if saveVersion >= 7 {
		b.uint32()
	}
	if saveVersion >= 8 {
		b.string()
	}
	b.uint32()
	if saveVersion >= 10 {
		b.string()
	}
	if saveVersion >= 13 {
		b.uint32()
		b.uint32()
		b.uint64()
		b.uint64()
		h.IsCreativeModeOn = b.uint32() != 0
	}
	if b.err != nil {
		return saveHeader{}, b.err
	}
	return h, nil
}
