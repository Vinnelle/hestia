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
	"regexp"
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

// frameSrc is derived from the registry so services.go stays the only place a
// service is declared. Get this wrong and our own CSP silently blanks the frame.
// Non-frameable services are excluded: they open in a new tab and never load
// here, so listing them would only widen the policy for nothing.
var frameSrc = func() string {
	var origins []string
	for _, s := range services {
		if s.Frameable {
			origins = append(origins, "https://"+s.Host)
		}
	}
	return strings.Join(origins, " ")
}()

var securityHeaders = map[string]string{
	// The portal is the framer and must never itself be framed: anyone able to
	// frame it would be framing every service through it.
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

var hashedAsset = regexp.MustCompile(`\.[0-9a-f]{8}\.(css|js)$`)

// assetCache mirrors what the nginx sites next door serve: content-hashed CSS/JS
// is immutable, fonts and images get a month, anything else revalidates. Without
// an explicit header Cloudflare applies its own default browser TTL, which
// leaves returning browsers running stale JS against freshly rendered HTML.
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

// userFromRequest reads the identity Authelia handed to ingress-nginx. The
// auth-response-headers list in hestia/locals.tf makes nginx overwrite any
// client-supplied Remote-* header with the value from Authelia's auth response,
// so a caller arriving through the ingress cannot forge these. The portal is
// ClusterIP-only and has no other route in.
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

// The cluster read costs three API calls, and Home polls it. Cache briefly so a
// left-open tab does not hammer the apiserver.
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

	// A portal that cannot reach the apiserver should still list services, so
	// this is a warning rather than a fatal.
	kube, err := newKubeClient()
	if err != nil {
		log.Printf("kubernetes client unavailable, cluster stats disabled: %v", err)
	}
	cache := &statsCache{kube: kube, ttl: 15 * time.Second}

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

	// Read by the apex site at vinnel.cloud to decide whether to offer a login
	// link or a link straight into the portal. Unauthenticated callers never
	// reach this: forward-auth redirects them to Authelia, which sends no CORS
	// headers, so the apex's fetch rejects and it falls back to "login".
	mux.HandleFunc("GET /api/me", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "https://vinnel.cloud")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Vary", "Origin")
		writeJSON(w, map[string]string{"email": userFromRequest(r)})
	})

	mux.HandleFunc("GET /api/cluster", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, cache.get())
	})

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		for k, v := range securityHeaders {
			w.Header().Set(k, v)
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		// The page is rendered per-user and carries the signed-in email.
		w.Header().Set("Cache-Control", "no-store")
		if err := tmpl.Execute(w, pageData{User: userFromRequest(r), Services: services}); err != nil {
			log.Printf("render portal: %v", err)
		}
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           otelhttp.NewHandler(mux, "http"),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("vinnel-cloud-admin listening on %s", addr)
	log.Fatal(srv.ListenAndServe())
}
