package main

import (
	"context"
	"embed"
	"encoding/json"
	"html/template"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

//go:embed html
var htmlFS embed.FS

type pageData struct {
	User     string
	Services []service
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

var extraFrameSrc = []string{"https://auth.vinnel.cloud"}

var frameSrc = func() string {
	origins := append([]string{}, extraFrameSrc...)
	for _, s := range services {
		if s.Frameable {
			origins = append(origins, "https://"+s.Host)
		}
	}
	return strings.Join(origins, " ")
}()

var securityHeaders = map[string]string{
	"X-Frame-Options":        "DENY",
	"X-Content-Type-Options": "nosniff",
	"Referrer-Policy":        "strict-origin-when-cross-origin",
	"Content-Security-Policy": strings.Join([]string{
		"default-src 'self'",
		"script-src 'self'",
		"style-src 'self'",
		"img-src 'self' data:",
		"frame-src " + frameSrc,
		"object-src 'none'",
		"frame-ancestors 'none'",
		"base-uri 'self'",
		"form-action 'self'",
	}, "; "),
}

func nosniff(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		h.ServeHTTP(w, r)
	})
}

var hashedAsset = regexp.MustCompile(`\.[0-9a-f]{8}\.(css|js)$`)

func assetCache(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case hashedAsset.MatchString(r.URL.Path):
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		case strings.HasSuffix(r.URL.Path, ".webp"), strings.HasSuffix(r.URL.Path, ".woff2"):
			w.Header().Set("Cache-Control", "public, max-age=2592000, immutable")
		default:
			w.Header().Set("Cache-Control", "no-cache")
		}
		h.ServeHTTP(w, r)
	})
}

func userFromRequest(r *http.Request) string {
	if email := r.Header.Get("Remote-Email"); email != "" {
		return email
	}
	return r.Header.Get("Remote-User")
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("writeJSON: %v", err)
	}
}

type statsCache struct {
	mu   sync.Mutex
	at   time.Time
	val  clusterStats
	ttl  time.Duration
	kube *kubeClient
}

func (c *statsCache) get() clusterStats {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.kube == nil {
		return clusterStats{Err: "kubernetes API unavailable"}
	}
	if time.Since(c.at) < c.ttl {
		return c.val
	}
	c.val = c.kube.stats()
	c.at = time.Now()
	return c.val
}

func main() {
	addr := env("LISTEN_ADDR", ":8080")

	shutdownTracing, err := setupTracing(context.Background(), env("OTEL_COLLECTOR_ENDPOINT", ""))
	if err != nil {
		log.Fatalf("otel setup: %v", err)
	}
	defer shutdownTracing(context.Background())

	kube, err := newKubeClient()
	if err != nil {
		log.Printf("kubernetes client unavailable, cluster stats disabled: %v", err)
	}
	cache := &statsCache{kube: kube, ttl: 15 * time.Second}

	satisfactory := &satisfactoryService{
		kube:     kube,
		host:     env("SATISFACTORY_HOST", ""),
		savesDir: env("SATISFACTORY_SAVES_DIR", "/mnt/satisfactory-saves/saved/server"),
	}

	tmpl := template.Must(template.ParseFS(htmlFS, "html/index.html"))

	htmlRoot, err := fs.Sub(htmlFS, "html")
	if err != nil {
		log.Fatalf("embed sub: %v", err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	mux.Handle("GET /assets/", assetCache(http.FileServer(http.FS(htmlRoot))))

	mux.HandleFunc("GET /api/me", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "https://vinnel.cloud")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Vary", "Origin")
		writeJSON(w, map[string]string{"email": userFromRequest(r)})
	})

	mux.HandleFunc("GET /api/cluster", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, cache.get())
	})

	mux.HandleFunc("GET /api/gameservers/satisfactory", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, satisfactory.status())
	})

	mux.HandleFunc("GET /api/gameservers/satisfactory/logs", func(w http.ResponseWriter, r *http.Request) {
		lines := 200
		if v := r.URL.Query().Get("lines"); v != "" {
			if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 2000 {
				lines = n
			}
		}
		logs, err := satisfactory.logs(lines)
		if err != nil {
			writeJSON(w, map[string]string{"err": err.Error()})
			return
		}
		writeJSON(w, map[string]string{"logs": logs})
	})

	mux.HandleFunc("GET /api/gameservers/satisfactory/save", func(w http.ResponseWriter, r *http.Request) {
		path, err := satisfactory.saveFilePath()
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Disposition", `attachment; filename="`+filepath.Base(path)+`"`)
		http.ServeFile(w, r, path)
	})

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		for k, v := range securityHeaders {
			w.Header().Set(k, v)
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		if err := tmpl.Execute(w, pageData{User: userFromRequest(r), Services: services}); err != nil {
			log.Printf("render portal: %v", err)
		}
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           otelhttp.NewHandler(nosniff(mux), "http"),
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("vinnel-cloud-admin listening on %s", addr)
	log.Fatal(srv.ListenAndServe())
}
