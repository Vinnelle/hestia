package main

import (
	"context"
	"embed"
	"html/template"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

//go:embed web
var webFS embed.FS

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

func main() {
	addr := env("LISTEN_ADDR", ":8080")

	shutdownTracing, err := setupTracing(context.Background(), env("OTEL_COLLECTOR_ENDPOINT", ""))
	if err != nil {
		log.Fatalf("otel setup: %v", err)
	}
	defer shutdownTracing(context.Background())

	tmpl := template.Must(template.ParseFS(webFS, "web/index.html"))

	webRoot, err := fs.Sub(webFS, "web")
	if err != nil {
		log.Fatalf("embed sub: %v", err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})

	mux.Handle("GET /assets/", http.FileServer(http.FS(webRoot)))

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		for k, v := range securityHeaders {
			w.Header().Set(k, v)
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
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
