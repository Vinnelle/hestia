package gitlab

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func newClient(t *testing.T, mux *http.ServeMux) *Client {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("PRIVATE-TOKEN") != "token" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		mux.ServeHTTP(w, r)
	}))
	t.Cleanup(srv.Close)
	return &Client{BaseURL: srv.URL + "/api/v4", ProjectID: "7", Token: "token"}
}

func TestDiffsFollowsPages(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v4/projects/7/merge_requests/3/diffs", func(w http.ResponseWriter, r *http.Request) {
		page := r.URL.Query().Get("page")
		if page == "1" {
			w.Header().Set("X-Next-Page", "2")
		}
		json.NewEncoder(w).Encode([]Diff{{NewPath: "page-" + page}})
	})
	diffs, err := newClient(t, mux).Diffs(context.Background(), 3)
	if err != nil {
		t.Fatalf("Diffs: %v", err)
	}
	if len(diffs) != 2 || diffs[0].NewPath != "page-1" || diffs[1].NewPath != "page-2" {
		t.Fatalf("diffs = %+v, want page-1 then page-2", diffs)
	}
}

func TestFileEscapesThePathAndReportsMissingFiles(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v4/projects/7/repository/files/{path}/raw", func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("path") != "hestia/apps/x.tf" || r.URL.Query().Get("ref") != "abc" {
			http.NotFound(w, r)
			return
		}
		w.Write([]byte("content"))
	})
	c := newClient(t, mux)
	data, err := c.File(context.Background(), "hestia/apps/x.tf", "abc")
	if err != nil || string(data) != "content" {
		t.Fatalf("File = %q, %v; want content", data, err)
	}
	if _, err := c.File(context.Background(), "missing.tf", "abc"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing file: err = %v, want ErrNotFound", err)
	}
}

func TestCreateNoteSendsTheBody(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v4/projects/7/merge_requests/3/notes", func(w http.ResponseWriter, r *http.Request) {
		var in map[string]string
		json.NewDecoder(r.Body).Decode(&in)
		json.NewEncoder(w).Encode(Note{ID: 11, Body: in["body"]})
	})
	n, err := newClient(t, mux).CreateNote(context.Background(), 3, "hello")
	if err != nil || n.ID != 11 || n.Body != "hello" {
		t.Fatalf("CreateNote = %+v, %v", n, err)
	}
}

func TestErrorsCarryTheStatus(t *testing.T) {
	c := newClient(t, http.NewServeMux())
	c.Token = "wrong"
	_, err := c.MergeRequest(context.Background(), 3)
	if err == nil || errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v, want a 401 error", err)
	}
}
