package main

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestGravatarURL(t *testing.T) {
	want := "https://www.gravatar.com/avatar/f8306a75bcca21dc2fd181916a1df7efb5651f0bdea9dd32cc7c4efa0ca78693?d=mp"
	if got := gravatarURL("  A@vin.moe "); got != want {
		t.Errorf("got %s", got)
	}
}

func TestSessionFromRequest(t *testing.T) {
	a := &authenticator{secret: []byte("test-secret")}

	sign := func(s *session) string {
		raw, _ := json.Marshal(s)
		payload := base64.RawURLEncoding.EncodeToString(raw)
		return payload + "." + hex.EncodeToString(a.sign([]byte(payload)))
	}

	validValue := sign(&session{Email: "a@vin.moe", Exp: time.Now().Add(time.Hour).Unix()})
	expiredValue := sign(&session{Email: "a@vin.moe", Exp: time.Now().Add(-time.Hour).Unix()})
	tamperedValue := validValue[:len(validValue)-2] + "00"

	cases := []struct {
		name  string
		value string
		set   bool
		want  bool
	}{
		{"valid session", validValue, true, true},
		{"expired session", expiredValue, true, false},
		{"tampered signature", tamperedValue, true, false},
		{"malformed value", "not-a-valid-cookie", true, false},
		{"no cookie", "", false, false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r := httptest.NewRequest(http.MethodGet, "/", nil)
			if c.set {
				r.AddCookie(&http.Cookie{Name: "session", Value: c.value})
			}
			got := a.sessionFromRequest(r)
			if (got != nil) != c.want {
				t.Errorf("sessionFromRequest() = %v, want present=%v", got, c.want)
			}
		})
	}
}
