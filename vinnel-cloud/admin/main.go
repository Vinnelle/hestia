package main

import (
	"bufio"
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"vinnel-cloud-admin/internal/cluster"
	"vinnel-cloud-admin/internal/kube"
	"vinnel-cloud-admin/internal/minecraft"
	"vinnel-cloud-admin/internal/portal"
	"vinnel-cloud-admin/internal/satisfactory"
	"vinnel-cloud-admin/internal/telemetry"
)

//go:embed html
var htmlFS embed.FS

const streamHeartbeat = 20 * time.Second

type pageData struct {
	User          string
	Services      []portal.Service
	ServiceGroups []portal.Group
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
	for _, s := range portal.Services {
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

func logLines(r *http.Request) int {
	if v := r.URL.Query().Get("lines"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 2000 {
			return n
		}
	}
	return 200
}

func commandHandler(audit string, run func(string) (string, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Command string `json:"command"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&req); err != nil {
			writeJSON(w, map[string]string{"err": "malformed request"})
			return
		}
		log.Printf("%s: user=%q command=%q", audit, userFromRequest(r), req.Command)
		out, err := run(req.Command)
		if err != nil {
			writeJSON(w, map[string]string{"err": err.Error()})
			return
		}
		writeJSON(w, map[string]string{"output": out})
	}
}

func streamHandler(open func(context.Context, int) (io.ReadCloser, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		src, err := open(r.Context(), logLines(r))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadGateway)
			return
		}
		defer src.Close()

		w.Header().Set("Content-Type", "text/event-stream")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Accel-Buffering", "no")
		w.WriteHeader(http.StatusOK)
		ctrl := http.NewResponseController(w)
		ctrl.Flush()

		lines := make(chan string, 256)
		go func() {
			defer close(lines)
			sc := bufio.NewScanner(src)
			sc.Buffer(make([]byte, 0, 64<<10), 1<<20)
			for sc.Scan() {
				select {
				case lines <- sc.Text():
				case <-r.Context().Done():
					return
				}
			}
		}()

		beat := time.NewTicker(streamHeartbeat)
		defer beat.Stop()
		for {
			select {
			case <-r.Context().Done():
				return
			case line, ok := <-lines:
				if !ok {
					return
				}
				if _, err := fmt.Fprintf(w, "data: %s\n\n", strings.TrimRight(line, "\r")); err != nil {
					return
				}
				ctrl.Flush()
			case <-beat.C:
				if _, err := io.WriteString(w, ": beat\n\n"); err != nil {
					return
				}
				ctrl.Flush()
			}
		}
	}
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
	val  cluster.Stats
	ttl  time.Duration
	kube *kube.Client
}

func (c *statsCache) get() cluster.Stats {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.kube == nil {
		return cluster.Stats{Err: "kubernetes API unavailable"}
	}
	if time.Since(c.at) < c.ttl {
		return c.val
	}
	c.val = cluster.Collect(c.kube)
	c.at = time.Now()
	return c.val
}

func main() {
	addr := env("LISTEN_ADDR", ":8080")

	shutdownTracing, err := telemetry.Setup(context.Background(), env("OTEL_COLLECTOR_ENDPOINT", ""))
	if err != nil {
		log.Fatalf("otel setup: %v", err)
	}
	defer shutdownTracing(context.Background())

	kubeClient, err := kube.New()
	if err != nil {
		log.Printf("kubernetes client unavailable, cluster stats disabled: %v", err)
	}
	cache := &statsCache{kube: kubeClient, ttl: 15 * time.Second}

	satisfactorySvc := &satisfactory.Service{
		Kube:          kubeClient,
		Host:          env("SATISFACTORY_HOST", ""),
		SavesURL:      env("SATISFACTORY_SAVES_URL", "http://satisfactory-saves.server.svc.cluster.local:8080"),
		AdminPassword: os.Getenv("SATISFACTORY_ADMIN_PASSWORD"),
	}

	mcPort, err := strconv.Atoi(env("MINECRAFT_PORT", "25565"))
	if err != nil {
		log.Fatalf("MINECRAFT_PORT: %v", err)
	}
	minecraftSvc := &minecraft.Service{
		Kube:         kubeClient,
		Host:         env("MINECRAFT_HOST", ""),
		Port:         mcPort,
		Address:      env("MINECRAFT_ADDRESS", "mc.vin.moe"),
		RconAddr:     env("MINECRAFT_RCON_ADDR", ""),
		RconPassword: os.Getenv("MINECRAFT_RCON_PASSWORD"),
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
		writeJSON(w, satisfactorySvc.Status())
	})

	mux.HandleFunc("GET /api/gameservers/satisfactory/logs/stream", streamHandler(satisfactorySvc.LogStream))

	mux.HandleFunc("GET /api/gameservers/minecraft/logs/stream", streamHandler(minecraftSvc.LogStream))

	mux.HandleFunc("GET /api/gameservers/satisfactory/save", func(w http.ResponseWriter, r *http.Request) {
		if err := satisfactorySvc.WriteSaveFile(w); err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
		}
	})

	mux.HandleFunc("GET /api/gameservers/minecraft", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, minecraftSvc.Status())
	})

	mux.HandleFunc("POST /api/gameservers/minecraft/command", commandHandler("minecraft rcon", minecraftSvc.Command))

	mux.HandleFunc("POST /api/gameservers/satisfactory/command", commandHandler("satisfactory api", satisfactorySvc.Command))

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		for k, v := range securityHeaders {
			w.Header().Set(k, v)
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		if err := tmpl.Execute(w, pageData{User: userFromRequest(r), Services: portal.Services, ServiceGroups: portal.Groups()}); err != nil {
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
