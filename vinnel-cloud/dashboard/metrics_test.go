package main

import (
	"database/sql"
	"encoding/json"
	"net/http/httptest"
	"testing"
	"time"

	_ "modernc.org/sqlite"
)

func TestHandleMetrics(t *testing.T) {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	if _, err := db.Exec(`CREATE TABLE hits (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		ts INTEGER NOT NULL,
		path TEXT NOT NULL,
		email TEXT NOT NULL,
		session_id TEXT NOT NULL
	)`); err != nil {
		t.Fatal(err)
	}

	now := time.Now()
	insert := func(daysAgo int, path, email, sessionID string) {
		ts := now.AddDate(0, 0, -daysAgo).Unix()
		if _, err := db.Exec(`INSERT INTO hits (ts, path, email, session_id) VALUES (?, ?, ?, ?)`,
			ts, path, email, sessionID); err != nil {
			t.Fatal(err)
		}
	}
	insert(0, "/metrics.html", "a@vin.moe", "s1")
	insert(1, "/metrics.html", "a@vin.moe", "s1")
	insert(1, "/account.html", "b@vin.moe", "s2")
	insert(40, "/metrics.html", "a@vin.moe", "s1") // outside the 30-day window

	w := httptest.NewRecorder()
	handleMetrics(db, w, httptest.NewRequest("GET", "/api/metrics", nil))

	var resp metricsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.Pageviews != 3 {
		t.Errorf("Pageviews = %d, want 3", resp.Pageviews)
	}
	if resp.Sessions != 2 {
		t.Errorf("Sessions = %d, want 2", resp.Sessions)
	}
	if resp.Users != 2 {
		t.Errorf("Users = %d, want 2", resp.Users)
	}
	if len(resp.Pages) != 2 || resp.Pages[0].Path != "/metrics.html" || resp.Pages[0].Views != 2 {
		t.Errorf("Pages = %+v, want /metrics.html first with 2 views", resp.Pages)
	}
}
