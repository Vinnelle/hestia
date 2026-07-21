package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

type session struct {
	Email   string `json:"email"`
	Name    string `json:"name"`
	Picture string `json:"picture"`
	Exp     int64  `json:"exp"`
}

type authenticator struct {
	oauth2Config *oauth2.Config
	verifier     *oidc.IDTokenVerifier
	secret       []byte
	secure       bool
}

func newAuthenticator(ctx context.Context, issuer, clientID, clientSecret, baseURL string, secret []byte) (*authenticator, error) {
	provider, err := oidc.NewProvider(ctx, issuer)
	if err != nil {
		return nil, err
	}
	return &authenticator{
		oauth2Config: &oauth2.Config{
			ClientID:     clientID,
			ClientSecret: clientSecret,
			RedirectURL:  baseURL + "/auth/callback",
			Endpoint:     provider.Endpoint(),
			Scopes:       []string{oidc.ScopeOpenID, "profile", "email"},
		},
		verifier: provider.Verifier(&oidc.Config{ClientID: clientID}),
		secret:   secret,
		secure:   strings.HasPrefix(baseURL, "https://"),
	}, nil
}

func randString() string {
	b := make([]byte, 32)
	rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

func (a *authenticator) handleLogin(w http.ResponseWriter, r *http.Request) {
	state := randString()
	verifier := oauth2.GenerateVerifier()

	a.setShortCookie(w, "oauth_state", state)
	a.setShortCookie(w, "oauth_verifier", verifier)

	url := a.oauth2Config.AuthCodeURL(state, oauth2.S256ChallengeOption(verifier))
	http.Redirect(w, r, url, http.StatusFound)
}

func (a *authenticator) handleCallback(w http.ResponseWriter, r *http.Request) {
	stateCookie, err := r.Cookie("oauth_state")
	if err != nil || r.URL.Query().Get("state") != stateCookie.Value {
		http.Error(w, "invalid oauth state", http.StatusBadRequest)
		return
	}
	verifierCookie, err := r.Cookie("oauth_verifier")
	if err != nil {
		http.Error(w, "missing pkce verifier", http.StatusBadRequest)
		return
	}

	token, err := a.oauth2Config.Exchange(r.Context(), r.URL.Query().Get("code"), oauth2.VerifierOption(verifierCookie.Value))
	if err != nil {
		http.Error(w, "token exchange failed", http.StatusBadGateway)
		return
	}
	rawIDToken, ok := token.Extra("id_token").(string)
	if !ok {
		http.Error(w, "no id_token in response", http.StatusBadGateway)
		return
	}
	idToken, err := a.verifier.Verify(r.Context(), rawIDToken)
	if err != nil {
		http.Error(w, "id_token verification failed", http.StatusUnauthorized)
		return
	}
	var claims struct {
		Email string `json:"email"`
		Name  string `json:"name"`
	}
	if err := idToken.Claims(&claims); err != nil {
		http.Error(w, "invalid claims", http.StatusUnauthorized)
		return
	}

	a.setSession(w, &session{
		Email:   claims.Email,
		Name:    claims.Name,
		Picture: gravatarURL(claims.Email),
		Exp:     time.Now().Add(24 * time.Hour).Unix(),
	})
	a.clearCookie(w, "oauth_state")
	a.clearCookie(w, "oauth_verifier")
	http.Redirect(w, r, "/metrics.html", http.StatusFound)
}

func (a *authenticator) handleLogout(w http.ResponseWriter, r *http.Request) {
	a.clearCookie(w, "session")
	http.Redirect(w, r, "/login.html", http.StatusFound)
}

func (a *authenticator) requireSession(next func(http.ResponseWriter, *http.Request, *session)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s := a.sessionFromRequest(r)
		if s == nil {
			http.Error(w, "unauthenticated", http.StatusUnauthorized)
			return
		}
		next(w, r, s)
	}
}

func (a *authenticator) sessionFromRequest(r *http.Request) *session {
	c, err := r.Cookie("session")
	if err != nil {
		return nil
	}
	payload, sig, ok := strings.Cut(c.Value, ".")
	if !ok || !hmac.Equal(mustDecodeHex(sig), a.sign([]byte(payload))) {
		return nil
	}
	raw, err := base64.RawURLEncoding.DecodeString(payload)
	if err != nil {
		return nil
	}
	var s session
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil
	}
	if time.Now().Unix() > s.Exp {
		return nil
	}
	return &s
}

func (a *authenticator) setSession(w http.ResponseWriter, s *session) {
	raw, _ := json.Marshal(s)
	payload := base64.RawURLEncoding.EncodeToString(raw)
	value := payload + "." + hex.EncodeToString(a.sign([]byte(payload)))
	http.SetCookie(w, &http.Cookie{
		Name:     "session",
		Value:    value,
		Path:     "/",
		HttpOnly: true,
		Secure:   a.secure,
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Unix(s.Exp, 0),
	})
}

func (a *authenticator) sign(data []byte) []byte {
	mac := hmac.New(sha256.New, a.secret)
	mac.Write(data)
	return mac.Sum(nil)
}

func (a *authenticator) setShortCookie(w http.ResponseWriter, name, value string) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    value,
		Path:     "/",
		HttpOnly: true,
		Secure:   a.secure,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   300,
	})
}

func (a *authenticator) clearCookie(w http.ResponseWriter, name string) {
	http.SetCookie(w, &http.Cookie{
		Name:     name,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Secure:   a.secure,
		MaxAge:   -1,
	})
}

// Authelia issues no picture claim (authentik did) — derive avatar from email
func gravatarURL(email string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	return "https://www.gravatar.com/avatar/" + hex.EncodeToString(sum[:]) + "?d=mp"
}

func mustDecodeHex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		return nil
	}
	return b
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		fmt.Println("writeJSON:", err)
	}
}
