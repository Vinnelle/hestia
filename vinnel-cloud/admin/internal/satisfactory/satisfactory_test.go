package satisfactory

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// jsonAutoindexServer fakes the nginx `autoindex_format json;` listing the
// satisfactory-saves-http sidecar serves.
func jsonAutoindexServer(t *testing.T, entries []map[string]string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(entries)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestLatestSaveFile(t *testing.T) {
	now := time.Now().UTC()
	srv := jsonAutoindexServer(t, []map[string]string{
		{"name": "autosave_0.sav", "type": "file", "mtime": now.Add(-time.Hour).Format(http.TimeFormat)},
		{"name": "autosave_1.sav", "type": "file", "mtime": now.Format(http.TimeFormat)},
		{"name": "ignored.txt", "type": "file", "mtime": now.Format(http.TimeFormat)},
	})

	got, err := latestSaveFile(srv.URL)
	if err != nil {
		t.Fatalf("latestSaveFile: %v", err)
	}
	if got.Name != "autosave_1.sav" {
		t.Errorf("latestSaveFile.Name = %q, want %q", got.Name, "autosave_1.sav")
	}
	if want := srv.URL + "/autosave_1.sav"; got.URL != want {
		t.Errorf("latestSaveFile.URL = %q, want %q", got.URL, want)
	}

	empty := jsonAutoindexServer(t, nil)
	if _, err := latestSaveFile(empty.URL); err == nil {
		t.Fatal("expected error for listing with no .sav files")
	}
}
