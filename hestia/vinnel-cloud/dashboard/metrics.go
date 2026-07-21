package main

import (
	"database/sql"
	"net/http"
	"time"
)

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
		MaxAge:   int((365 * 24 * time.Hour).Seconds()),
	})
	return id
}

func recordHit(db *sql.DB, path, email, sessionID string) {
	_, _ = db.Exec(`INSERT INTO hits (ts, path, email, session_id) VALUES (?, ?, ?, ?)`,
		time.Now().Unix(), path, email, sessionID)
}

type dailyCount struct {
	Day   string `json:"day"`
	Count int    `json:"count"`
}

type pageCount struct {
	Path  string `json:"path"`
	Views int    `json:"views"`
}

type metricsResponse struct {
	Pageviews int          `json:"pageviews"`
	Sessions  int          `json:"sessions"`
	Users     int          `json:"users"`
	Daily     []dailyCount `json:"daily"`
	Pages     []pageCount  `json:"pages"`
}

func handleMetrics(db *sql.DB, w http.ResponseWriter, r *http.Request) {
	since := time.Now().AddDate(0, 0, -30).Unix()
	resp := metricsResponse{Daily: []dailyCount{}, Pages: []pageCount{}}

	db.QueryRow(`SELECT COUNT(*) FROM hits WHERE ts >= ?`, since).Scan(&resp.Pageviews)
	db.QueryRow(`SELECT COUNT(DISTINCT session_id) FROM hits WHERE ts >= ?`, since).Scan(&resp.Sessions)
	db.QueryRow(`SELECT COUNT(DISTINCT email) FROM hits WHERE ts >= ?`, since).Scan(&resp.Users)

	rows, err := db.Query(`
		SELECT date(ts, 'unixepoch') AS day, COUNT(*)
		FROM hits WHERE ts >= ?
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

	rows, err = db.Query(`
		SELECT path, COUNT(*) AS views
		FROM hits WHERE ts >= ?
		GROUP BY path ORDER BY views DESC LIMIT 10`, since)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var p pageCount
			if rows.Scan(&p.Path, &p.Views) == nil {
				resp.Pages = append(resp.Pages, p)
			}
		}
	}

	writeJSON(w, resp)
}
