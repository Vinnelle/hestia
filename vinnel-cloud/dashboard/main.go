package main

import (
	"context"
	"database/sql"
	"embed"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	_ "modernc.org/sqlite"
)

//go:embed web
var webFS embed.FS

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("missing required env var %s", key)
	}
	return v
}

func main() {
	cfg := struct {
		issuer       string
		clientID     string
		clientSecret string
		baseURL      string
		cookieSecret string
		dbPath       string
		addr         string
		otelEndpoint string
	}{
		issuer:       mustEnv("OIDC_ISSUER"),
		clientID:     mustEnv("OIDC_CLIENT_ID"),
		clientSecret: mustEnv("OIDC_CLIENT_SECRET"),
		baseURL:      mustEnv("BASE_URL"),
		cookieSecret: mustEnv("COOKIE_SECRET"),
		dbPath:       env("DB_PATH", "/data/dashboard.db"),
		addr:         env("LISTEN_ADDR", ":8080"),
		otelEndpoint: env("OTEL_COLLECTOR_ENDPOINT", ""),
	}

	shutdownTracing, err := setupTracing(context.Background(), cfg.otelEndpoint)
	if err != nil {
		log.Fatalf("otel setup: %v", err)
	}
	defer shutdownTracing(context.Background())

	db, err := openDB(cfg.dbPath)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	auth, err := newAuthenticator(context.Background(), cfg.issuer, cfg.clientID, cfg.clientSecret, cfg.baseURL, []byte(cfg.cookieSecret))
	if err != nil {
		log.Fatalf("oidc setup: %v", err)
	}

	webRoot, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("embed sub: %v", err)
	}
	staticHandler := http.FileServer(http.FS(webRoot))

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	mux.HandleFunc("GET /auth/login", auth.handleLogin)
	mux.HandleFunc("GET /auth/callback", auth.handleCallback)
	mux.HandleFunc("POST /auth/logout", auth.handleLogout)

	mux.HandleFunc("GET /api/me", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "https://vinnel.cloud")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Vary", "Origin")
		auth.requireSession(func(w http.ResponseWriter, r *http.Request, s *session) {
			writeJSON(w, s)
		})(w, r)
	})
	mux.HandleFunc("GET /api/metrics", auth.requireSession(func(w http.ResponseWriter, r *http.Request, s *session) {
		handleMetrics(db, w, r)
	}))

	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" {
			http.Redirect(w, r, "/metrics.html", http.StatusFound)
			return
		}
		if !isAsset(r.URL.Path) && r.URL.Path != "/login.html" {
			s := auth.sessionFromRequest(r)
			if s == nil {
				http.Redirect(w, r, "/login.html", http.StatusFound)
				return
			}
			if _, err := fs.Stat(webRoot, strings.TrimPrefix(r.URL.Path, "/")); err == nil {
				recordHit(db, r.URL.Path, s.Email, sessionIDCookie(w, r))
			}
		}
		staticHandler.ServeHTTP(w, r)
	})

	srv := &http.Server{
		Addr:              cfg.addr,
		Handler:           otelhttp.NewHandler(mux, "http"),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("vinnel-cloud-dashboard listening on %s", cfg.addr)
	log.Fatal(srv.ListenAndServe())
}

func isAsset(p string) bool {
	return strings.HasPrefix(p, "/assets/")
}

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS hits (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		ts INTEGER NOT NULL,
		path TEXT NOT NULL,
		email TEXT NOT NULL,
		session_id TEXT NOT NULL
	)`)
	if err != nil {
		return nil, err
	}
	_, err = db.Exec(`CREATE INDEX IF NOT EXISTS idx_hits_ts ON hits(ts)`)
	return db, err
}
