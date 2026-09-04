package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"embed"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io"
	"io/fs"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/getsentry/sentry-go"
	sentryhttp "github.com/getsentry/sentry-go/http"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"vinnel-cloud-admin/internal/blog"
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
	Nonce         string
	MediaOrigin   string
	FilesOrigin   string
	Services      []portal.Service
	ServiceGroups []portal.Group
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func setupSentry() error {
	dsn := os.Getenv("SENTRY_DSN")
	if dsn == "" {
		return nil
	}
	return sentry.Init(sentry.ClientOptions{
		Dsn:              dsn,
		EnableTracing:    true,
		TracesSampleRate: 0.1,
		Environment:      env("SENTRY_ENVIRONMENT", "production"),
	})
}

func envDuration(key string, def time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		log.Fatalf("%s: %v", key, err)
	}
	return d
}

func runGameSleeper(mc *minecraft.Service, sf *satisfactory.Service) {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	idle := envDuration("GAME_IDLE_TIMEOUT", 15*time.Minute)
	poll := envDuration("GAME_SLEEP_POLL", 30*time.Second)

	sleeper := &minecraft.Sleeper{
		Service:     mc,
		Addr:        env("MINECRAFT_SLEEPER_ADDR", ""),
		IdleTimeout: idle,
		Poll:        poll,
		MOTD:        env("MINECRAFT_SLEEP_MOTD", ""),
	}
	idler := &satisfactory.Idler{Service: sf, IdleTimeout: idle, Poll: poll}

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		if err := sleeper.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			log.Printf("minecraft sleeper: %v", err)
		}
	}()
	go func() {
		defer wg.Done()
		if err := idler.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			log.Printf("satisfactory idler: %v", err)
		}
	}()
	wg.Wait()
}

func runBlogSync() {
	store, err := blog.NewStore(env("BLOG_DATA_DIR", "/data/posts"))
	if err != nil {
		log.Fatalf("blog store: %v", err)
	}
	repo := &blog.Repo{
		BaseURL:   env("GITLAB_API_URL", "https://gitlab.vinnel.cloud/api/v4"),
		ProjectID: env("GITLAB_PROJECT_ID", ""),
		Token:     os.Getenv("GITLAB_TOKEN"),
		Branch:    env("BLOG_BRANCH", "pre"),
		PostsPath: env("BLOG_POSTS_PATH", "hestia/sites/vin-moe/site/posts"),
	}
	posts, err := store.All()
	if err != nil {
		log.Fatalf("blog sync store: %v", err)
	}
	if err := repo.Sync(context.Background(), posts, "nightly sync"); err != nil {
		log.Fatalf("blog sync: %v", err)
	}
}

func postLinkBase(publicURL string) string {
	if publicURL == "" {
		return ""
	}
	return publicURL + "/posts/"
}

func purgeTargets(siteURL, publicURL string) []string {
	urls := []string{}
	for _, host := range []string{strings.TrimRight(siteURL, "/"), publicURL} {
		if host == "" {
			continue
		}
		urls = append(urls, host+"/", host+"/posts.json", host+"/feed.xml", host+"/sitemap.xml")
	}
	return urls
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
}

func contentSecurityPolicy(nonce string, connectOrigins ...string) string {
	style := "style-src 'self'"
	if nonce != "" {
		style += " 'nonce-" + nonce + "'"
	}
	connect := "'self'"
	for _, origin := range connectOrigins {
		if origin != "" {
			connect += " " + origin
		}
	}
	return strings.Join([]string{
		"default-src 'self'",
		"script-src 'self'",
		style,
		"connect-src " + connect,
		"img-src 'self' data:",
		"frame-src " + frameSrc,
		"object-src 'none'",
		"frame-ancestors 'none'",
		"base-uri 'self'",
		"form-action 'self'",
	}, "; ")
}

func originOf(raw string) string {
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Scheme == "" || parsed.Host == "" {
		return ""
	}
	return parsed.Scheme + "://" + parsed.Host
}

func newNonce() string {
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		return ""
	}
	return base64.RawStdEncoding.EncodeToString(buf)
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

func scaleHandler(audit string, run func() error) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s: user=%q", audit, userFromRequest(r))
		if err := run(); err != nil {
			writeJSON(w, map[string]string{"err": err.Error()})
			return
		}
		writeJSON(w, map[string]string{"ok": "true"})
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

type blogAPI struct {
	store     *blog.Store
	media     *blog.Media
	repo      *blog.Repo
	purger    *blog.Purger
	feed      blog.FeedConfig
	publicURL string
}

func (b *blogAPI) purge(ctx context.Context, extra ...string) {
	if err := b.purger.Purge(ctx, extra...); err != nil {
		log.Printf("blog purge: %v", err)
	}
}

func (b *blogAPI) postURL(slug string) string {
	if b.publicURL != "" {
		return b.publicURL + "/posts/" + slug
	}
	return strings.TrimRight(b.feed.SiteURL, "/") + "/posts/" + slug
}

func (b *blogAPI) mediaURL(name string) string {
	if b.publicURL != "" {
		return b.publicURL + "/media/" + name
	}
	return "/public/media/" + name
}

const publicCacheControl = "public, max-age=0, must-revalidate, s-maxage=300"
const adminOrigin = "https://admin.vinnel.cloud"

func servePublic(w http.ResponseWriter, r *http.Request, contentType string, body []byte) {
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cache-Control", publicCacheControl)
	w.Header().Set("ETag", fmt.Sprintf(`"%x"`, sha256.Sum256(body)))
	http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(body))
}

func (b *blogAPI) publicPosts(w http.ResponseWriter, r *http.Request) {
	posts, err := b.store.Published()
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	body, err := json.Marshal(map[string]any{"posts": posts})
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	servePublic(w, r, "application/json; charset=utf-8", body)
}

func (b *blogAPI) publicFeed(w http.ResponseWriter, r *http.Request) {
	posts, err := b.store.Published()
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	body, err := blog.Feed(b.feed, posts)
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	servePublic(w, r, "application/atom+xml; charset=utf-8", body)
}

func (b *blogAPI) publicSitemap(w http.ResponseWriter, r *http.Request) {
	posts, err := b.store.Published()
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	body, err := blog.Sitemap(b.feed, posts)
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	servePublic(w, r, "application/xml; charset=utf-8", body)
}

func (b *blogAPI) publicPost(w http.ResponseWriter, r *http.Request) {
	post, err := b.store.Get(r.PathValue("slug"))
	if err != nil || post.Draft {
		http.NotFound(w, r)
		return
	}
	rendered, err := blog.RenderHTML(post.Body)
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	body, err := blog.Page(b.feed, blog.Rendered{Slug: post.Slug, Title: post.Title, Date: post.Date, HTML: rendered})
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	servePublic(w, r, "text/html; charset=utf-8", body)
}

func (b *blogAPI) publicMedia(w http.ResponseWriter, r *http.Request) {
	b.media.Serve(w, r, r.PathValue("name"))
}

func (b *blogAPI) upload(w http.ResponseWriter, r *http.Request) {
	if !allowUploadOrigin(w, r) {
		return
	}
	reader, err := r.MultipartReader()
	if err != nil {
		b.fail(w, fmt.Errorf("%w: malformed request", blog.ErrInvalid))
		return
	}

	for {
		part, err := reader.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			b.fail(w, fmt.Errorf("%w: malformed request", blog.ErrInvalid))
			return
		}
		if part.FormName() != "file" {
			part.Close()
			continue
		}
		name := part.FileName()
		if name == "" {
			part.Close()
			b.fail(w, fmt.Errorf("%w: file name is required", blog.ErrInvalid))
			return
		}
		stored, err := b.media.SaveReader(name, part)
		part.Close()
		if err != nil {
			b.fail(w, err)
			return
		}
		log.Printf("blog upload: user=%q name=%q", userFromRequest(r), stored)
		writeJSON(w, map[string]string{"name": stored, "url": b.mediaURL(stored)})
		return
	}
	b.fail(w, fmt.Errorf("%w: file is required", blog.ErrInvalid))
}

func (b *blogAPI) uploadStart(w http.ResponseWriter, r *http.Request) {
	if !allowUploadOrigin(w, r) {
		return
	}
	var in struct {
		Filename  string `json:"filename"`
		Size      int64  `json:"size"`
		ChunkSize int64  `json:"chunkSize"`
	}
	if err := json.NewDecoder(io.LimitReader(r.Body, 4096)).Decode(&in); err != nil {
		b.fail(w, fmt.Errorf("%w: malformed request", blog.ErrInvalid))
		return
	}
	var status *blog.UploadStatus
	var err error
	if in.ChunkSize > 0 {
		status, err = b.media.StartUploadWithChunkSize(in.Filename, in.Size, in.ChunkSize)
	} else {
		status, err = b.media.StartUpload(in.Filename, in.Size)
	}
	if err != nil {
		b.fail(w, err)
		return
	}
	writeJSON(w, status)
}

func (b *blogAPI) uploadStatus(w http.ResponseWriter, r *http.Request) {
	if !allowUploadOrigin(w, r) {
		return
	}
	status, err := b.media.UploadStatus(r.PathValue("id"))
	if err != nil {
		b.fail(w, err)
		return
	}
	writeJSON(w, status)
}

func (b *blogAPI) uploadChunk(w http.ResponseWriter, r *http.Request) {
	if !allowUploadOrigin(w, r) {
		return
	}
	index, err := strconv.ParseInt(r.PathValue("index"), 10, 64)
	if err != nil {
		b.fail(w, fmt.Errorf("%w: invalid chunk index", blog.ErrInvalid))
		return
	}
	if err := b.media.UploadChunk(r.PathValue("id"), index, r.Body); err != nil {
		b.fail(w, err)
		return
	}
	writeJSON(w, map[string]string{"ok": "true"})
}

func (b *blogAPI) uploadComplete(w http.ResponseWriter, r *http.Request) {
	if !allowUploadOrigin(w, r) {
		return
	}
	name, err := b.media.CompleteUpload(r.PathValue("id"))
	if err != nil {
		b.fail(w, err)
		return
	}
	log.Printf("blog upload complete: user=%q name=%q", userFromRequest(r), name)
	writeJSON(w, map[string]string{"name": name, "url": b.mediaURL(name)})
}

func allowUploadOrigin(w http.ResponseWriter, r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		return true
	}
	w.Header().Set("Vary", "Origin")
	if origin != adminOrigin {
		http.Error(w, "origin not allowed", http.StatusForbidden)
		return false
	}
	return true
}

func (b *blogAPI) uploadOptions(w http.ResponseWriter, r *http.Request) {
	if !allowUploadOrigin(w, r) {
		return
	}
	if r.Header.Get("Origin") == adminOrigin {
		w.Header().Set("Access-Control-Allow-Origin", adminOrigin)
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	}
	w.WriteHeader(http.StatusNoContent)
}

func (b *blogAPI) fail(w http.ResponseWriter, err error) {
	status := http.StatusInternalServerError
	switch {
	case errors.Is(err, blog.ErrNotFound):
		status = http.StatusNotFound
	case errors.Is(err, blog.ErrInvalid):
		status = http.StatusBadRequest
	}
	w.WriteHeader(status)
	writeJSON(w, map[string]string{"err": err.Error()})
}

func (b *blogAPI) list(w http.ResponseWriter, r *http.Request) {
	posts, err := b.store.List()
	if err != nil {
		b.fail(w, err)
		return
	}
	writeJSON(w, map[string]any{"posts": posts, "publishing": b.repo.Configured()})
}

func (b *blogAPI) get(w http.ResponseWriter, r *http.Request) {
	post, err := b.store.Get(r.PathValue("slug"))
	if err != nil {
		b.fail(w, err)
		return
	}
	writeJSON(w, post)
}

func (b *blogAPI) save(w http.ResponseWriter, r *http.Request) {
	var in blog.Post
	if err := json.NewDecoder(io.LimitReader(r.Body, blog.MaxBody+8192)).Decode(&in); err != nil {
		b.fail(w, fmt.Errorf("%w: malformed request", blog.ErrInvalid))
		return
	}
	in.Slug = r.PathValue("slug")
	if in.Date == "" {
		in.Date = time.Now().UTC().Format("2006-01-02")
	}
	if err := b.store.Save(&in); err != nil {
		b.fail(w, err)
		return
	}
	log.Printf("blog save: user=%q slug=%q draft=%v", userFromRequest(r), in.Slug, in.Draft)
	if !in.Draft {
		b.purge(r.Context(), b.postURL(in.Slug))
	}
	writeJSON(w, &in)
}

func (b *blogAPI) remove(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	user := userFromRequest(r)
	if err := b.store.Delete(slug); err != nil {
		b.fail(w, err)
		return
	}
	log.Printf("blog delete: user=%q slug=%q", user, slug)
	b.purge(r.Context(), b.postURL(slug))
	writeJSON(w, map[string]string{"ok": "true"})
}

func (b *blogAPI) publish(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	post, err := b.store.Get(slug)
	if err != nil {
		b.fail(w, err)
		return
	}
	user := userFromRequest(r)
	if !b.repo.Configured() {
		b.fail(w, fmt.Errorf("%w: repository sync is not configured", blog.ErrInvalid))
		return
	}
	post.Draft = false
	if err := b.store.Save(post); err != nil {
		b.fail(w, err)
		return
	}
	log.Printf("blog publish: user=%q slug=%q", user, slug)
	b.purge(r.Context(), b.postURL(slug))
	writeJSON(w, map[string]string{"ok": "true", "branch": b.repo.Branch})
}

func (b *blogAPI) unpublish(w http.ResponseWriter, r *http.Request) {
	slug := r.PathValue("slug")
	post, err := b.store.Get(slug)
	if err != nil {
		b.fail(w, err)
		return
	}
	user := userFromRequest(r)
	if !b.repo.Configured() {
		b.fail(w, fmt.Errorf("%w: repository sync is not configured", blog.ErrInvalid))
		return
	}
	post.Draft = true
	if err := b.store.Save(post); err != nil {
		b.fail(w, err)
		return
	}
	log.Printf("blog unpublish: user=%q slug=%q", user, slug)
	b.purge(r.Context(), b.postURL(slug))
	writeJSON(w, map[string]string{"ok": "true"})
}

func (b *blogAPI) slugify(w http.ResponseWriter, r *http.Request) {
	base := blog.Slugify(r.URL.Query().Get("title"))
	if base == "" {
		base = "post"
	}
	slug := base
	for i := 2; b.store.Exists(slug); i++ {
		slug = fmt.Sprintf("%s-%d", base, i)
	}
	writeJSON(w, map[string]string{"slug": slug})
}

func main() {
	addr := env("LISTEN_ADDR", ":8080")
	if err := setupSentry(); err != nil {
		log.Fatalf("sentry setup: %v", err)
	}
	if os.Getenv("SENTRY_DSN") != "" {
		defer sentry.Flush(2 * time.Second)
	}

	shutdownTracing, err := telemetry.Setup(context.Background(), env("OTEL_COLLECTOR_ENDPOINT", ""))
	if err != nil {
		log.Fatalf("otel setup: %v", err)
	}
	defer shutdownTracing(context.Background())

	role := env("ROLE", "dashboard")
	if role == "blog-sync" {
		runBlogSync()
		return
	}

	kubeClient, err := kube.New()
	if err != nil {
		log.Printf("kubernetes client unavailable, cluster stats disabled: %v", err)
	}
	cache := &statsCache{kube: kubeClient, ttl: 15 * time.Second}

	satisfactorySvc := &satisfactory.Service{
		Kube:          kubeClient,
		Host:          env("SATISFACTORY_HOST", ""),
		SavesURL:      env("SATISFACTORY_SAVES_URL", "http://satisfactory-saves.games.svc.cluster.local:8080"),
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

	if role == "game-sleeper" {
		runGameSleeper(minecraftSvc, satisfactorySvc)
		return
	}

	tmpl := template.Must(template.ParseFS(htmlFS, "html/index.html"))

	htmlRoot, err := fs.Sub(htmlFS, "html")
	if err != nil {
		log.Fatalf("embed sub: %v", err)
	}

	blogStore, err := blog.NewStore(env("BLOG_DATA_DIR", "/data/posts"))
	if err != nil {
		log.Fatalf("blog store: %v", err)
	}
	blogRepo := &blog.Repo{
		BaseURL:   env("GITLAB_API_URL", "https://gitlab.vinnel.cloud/api/v4"),
		ProjectID: env("GITLAB_PROJECT_ID", ""),
		Token:     os.Getenv("GITLAB_TOKEN"),
		Branch:    env("BLOG_BRANCH", "pre"),
		PostsPath: env("BLOG_POSTS_PATH", "hestia/sites/vin-moe/site/posts"),
	}
	blogMedia, err := blog.NewMedia(env("BLOG_MEDIA_DIR", "/data/media"))
	if err != nil {
		log.Fatalf("blog media: %v", err)
	}
	siteURL := env("BLOG_SITE_URL", "https://vin.moe")
	publicURL := strings.TrimRight(env("BLOG_PUBLIC_URL", ""), "/")
	filesOrigin := originOf(strings.TrimRight(env("BLOG_FILES_URL", "https://files.vinnel.cloud"), "/"))
	purgeURLs := purgeTargets(siteURL, publicURL)
	blogHandlers := &blogAPI{
		store:     blogStore,
		media:     blogMedia,
		repo:      blogRepo,
		publicURL: publicURL,
		purger: &blog.Purger{
			ZoneID: env("BLOG_ZONE_ID", ""),
			Token:  os.Getenv("CF_CACHE_PURGE_TOKEN"),
			URLs:   purgeURLs,
		},
		feed: blog.FeedConfig{
			Title:        env("BLOG_TITLE", "vin.moe"),
			Subtitle:     env("BLOG_SUBTITLE", "infrastructure, devops, software"),
			SiteURL:      siteURL,
			Author:       env("BLOG_AUTHOR", "Finlay"),
			Email:        env("BLOG_AUTHOR_EMAIL", ""),
			PostLinkBase: postLinkBase(publicURL),
		},
	}
	if !blogHandlers.purger.Configured() {
		log.Print("blog cache purge disabled: BLOG_ZONE_ID or CF_CACHE_PURGE_TOKEN unset")
	}
	if !blogRepo.Configured() {
		log.Print("blog repository sync disabled: GITLAB_PROJECT_ID or GITLAB_TOKEN unset")
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

	mux.HandleFunc("POST /api/gameservers/minecraft/start", scaleHandler("minecraft start", minecraftSvc.Start))

	mux.HandleFunc("POST /api/gameservers/minecraft/stop", scaleHandler("minecraft stop", minecraftSvc.Stop))

	mux.HandleFunc("POST /api/gameservers/satisfactory/start", scaleHandler("satisfactory start", satisfactorySvc.Start))
	mux.HandleFunc("POST /api/gameservers/satisfactory/stop", scaleHandler("satisfactory stop", satisfactorySvc.Stop))

	mux.HandleFunc("GET /public/posts.json", blogHandlers.publicPosts)
	mux.HandleFunc("GET /public/feed.xml", blogHandlers.publicFeed)
	mux.HandleFunc("GET /public/sitemap.xml", blogHandlers.publicSitemap)
	mux.HandleFunc("GET /public/posts/{slug}", blogHandlers.publicPost)
	mux.HandleFunc("GET /public/media/{name}", blogHandlers.publicMedia)

	mux.HandleFunc("GET /api/blog/posts", blogHandlers.list)
	mux.HandleFunc("GET /api/blog/slug", blogHandlers.slugify)
	mux.HandleFunc("POST /api/blog/media", blogHandlers.upload)
	mux.HandleFunc("OPTIONS /api/blog/media", blogHandlers.uploadOptions)
	mux.HandleFunc("POST /api/blog/media/uploads", blogHandlers.uploadStart)
	mux.HandleFunc("GET /api/blog/media/uploads/{id}", blogHandlers.uploadStatus)
	mux.HandleFunc("PUT /api/blog/media/uploads/{id}/chunks/{index}", blogHandlers.uploadChunk)
	mux.HandleFunc("POST /api/blog/media/uploads/{id}/complete", blogHandlers.uploadComplete)
	mux.HandleFunc("OPTIONS /api/blog/media/uploads/{path...}", blogHandlers.uploadOptions)
	mux.HandleFunc("GET /api/blog/posts/{slug}", blogHandlers.get)
	mux.HandleFunc("PUT /api/blog/posts/{slug}", blogHandlers.save)
	mux.HandleFunc("DELETE /api/blog/posts/{slug}", blogHandlers.remove)
	mux.HandleFunc("POST /api/blog/posts/{slug}/publish", blogHandlers.publish)
	mux.HandleFunc("POST /api/blog/posts/{slug}/unpublish", blogHandlers.unpublish)

	mediaOrigin := originOf(publicURL)

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		for k, v := range securityHeaders {
			w.Header().Set(k, v)
		}
		nonce := newNonce()
		w.Header().Set("Content-Security-Policy", contentSecurityPolicy(nonce, filesOrigin))
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		if err := tmpl.Execute(w, pageData{User: userFromRequest(r), Nonce: nonce, MediaOrigin: mediaOrigin, FilesOrigin: filesOrigin, Services: portal.Services, ServiceGroups: portal.Groups()}); err != nil {
			log.Printf("render portal: %v", err)
		}
	})

	handler := sentryhttp.New(sentryhttp.Options{}).Handle(otelhttp.NewHandler(nosniff(mux), "http"))
	srv := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("vinnel-cloud-admin listening on %s", addr)
	log.Fatal(srv.ListenAndServe())
}
