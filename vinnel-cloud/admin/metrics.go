package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"net/http"
	"time"
)

// Portal usage, carried over from the dashboard app this replaced. It counted
// page views on its own pages; here the equivalent signal is which service each
// tile opened, so the table records slugs rather than paths.

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS opens (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		ts INTEGER NOT NULL,
		slug TEXT NOT NULL,
		email TEXT NOT NULL,
		session_id TEXT NOT NULL
	)`); err != nil {
		return nil, err
	}
	_, err = db.Exec(`CREATE INDEX IF NOT EXISTS idx_opens_ts ON opens(ts)`)
	return db, err
}

func randString() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return base64.RawURLEncoding.EncodeToString(b)
}

// Distinguishes repeat visits from distinct ones without touching the Authelia
// session. Not a security control — it only groups rows in the usage chart.
func sessionIDCookie(w http.ResponseWriter, r *http.Request) string {
	if c, err := r.Cookie("vc_sid"); err == nil && c.Value != "" {
		return c.Value
	}
	id := randString()
	http.SetCookie(w, &http.Cookie{
		Name:     "vc_sid",
		Value:    id,
		Path:     "/",
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   int((365 * 24 * time.Hour).Seconds()),
	})
	return id
}

func recordOpen(db *sql.DB, slug, email, sessionID string) {
	_, _ = db.Exec(`INSERT INTO opens (ts, slug, email, session_id) VALUES (?, ?, ?, ?)`,
		time.Now().Unix(), slug, email, sessionID)
}

type dailyCount struct {
	Day   string `json:"day"`
	Count int    `json:"count"`
}

type serviceCount struct {
	Slug  string `json:"slug"`
	Label string `json:"label"`
	Opens int    `json:"opens"`
}

type usageResponse struct {
	Opens    int            `json:"opens"`
	Sessions int            `json:"sessions"`
	Users    int            `json:"users"`
	Daily    []dailyCount   `json:"daily"`
	Services []serviceCount `json:"services"`
}

func handleUsage(db *sql.DB, w http.ResponseWriter, r *http.Request) {
	since := time.Now().AddDate(0, 0, -30).Unix()
	resp := usageResponse{Daily: []dailyCount{}, Services: []serviceCount{}}

	db.QueryRow(`SELECT COUNT(*) FROM opens WHERE ts >= ?`, since).Scan(&resp.Opens)
	db.QueryRow(`SELECT COUNT(DISTINCT session_id) FROM opens WHERE ts >= ?`, since).Scan(&resp.Sessions)
	db.QueryRow(`SELECT COUNT(DISTINCT email) FROM opens WHERE ts >= ?`, since).Scan(&resp.Users)

	rows, err := db.Query(`
		SELECT date(ts, 'unixepoch') AS day, COUNT(*)
		FROM opens WHERE ts >= ?
		GROUP BY day ORDER BY day`, since)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var d dailyCount
			if rows.Scan(&d.Day, &d.Count) == nil {
				resp.Daily = append(resp.Daily, d)
			}
		}
	}

	labels := map[string]string{}
	for _, s := range services {
		labels[s.Slug] = s.Label
	}
	rows, err = db.Query(`
		SELECT slug, COUNT(*) AS opens
		FROM opens WHERE ts >= ?
		GROUP BY slug ORDER BY opens DESC LIMIT 10`, since)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var s serviceCount
			if rows.Scan(&s.Slug, &s.Opens) == nil {
				s.Label = labels[s.Slug]
				if s.Label == "" {
					s.Label = s.Slug
				}
				resp.Services = append(resp.Services, s)
			}
		}
	}

	writeJSON(w, resp)
}
