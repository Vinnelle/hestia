package satisfactory

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// jsonAutoindexServer fakes the nginx `autoindex_format json;` listing the
// satisfactory-saves-http sidecar serves.
func jsonAutoindexServer(t *testing.T, entries []map[string]string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(entries)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestLatestSaveFile(t *testing.T) {
	now := time.Now().UTC()
	srv := jsonAutoindexServer(t, []map[string]string{
		{"name": "autosave_0.sav", "type": "file", "mtime": now.Add(-time.Hour).Format(http.TimeFormat)},
		{"name": "autosave_1.sav", "type": "file", "mtime": now.Format(http.TimeFormat)},
		{"name": "ignored.txt", "type": "file", "mtime": now.Format(http.TimeFormat)},
	})

	got, err := latestSaveFile(srv.URL)
	if err != nil {
		t.Fatalf("latestSaveFile: %v", err)
	}
	if got.Name != "autosave_1.sav" {
		t.Errorf("latestSaveFile.Name = %q, want %q", got.Name, "autosave_1.sav")
	}
	if want := srv.URL + "/autosave_1.sav"; got.URL != want {
		t.Errorf("latestSaveFile.URL = %q, want %q", got.URL, want)
	}

	empty := jsonAutoindexServer(t, nil)
	if _, err := latestSaveFile(empty.URL); err == nil {
		t.Fatal("expected error for listing with no .sav files")
	}
}

// rewriteTransport redirects the fixed https://<host>:7777/api/v1 endpoint at a
// local test server.
type rewriteTransport struct{ target *url.URL }

func (t rewriteTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	c := r.Clone(r.Context())
	c.URL.Scheme = t.target.Scheme
	c.URL.Host = t.target.Host
	return http.DefaultTransport.RoundTrip(c)
}

type apiRequest struct {
	Function string            `json:"function"`
	Data     map[string]string `json:"data"`
	Auth     string            `json:"-"`
}

// fakeAPI serves the Dedicated Server HTTPS API against handle, and points both
// package clients at it for the duration of the test.
func fakeAPI(t *testing.T, handle func(apiRequest, http.ResponseWriter)) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var call apiRequest
		if err := json.NewDecoder(r.Body).Decode(&call); err != nil {
			t.Errorf("decode request: %v", err)
			return
		}
		call.Auth = r.Header.Get("Authorization")
		if call.Function == "RunCommand" && call.Auth == "" {
			t.Error("RunCommand sent no Authorization header")
		}
		handle(call, w)
	}))
	t.Cleanup(srv.Close)

	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatalf("parse test server URL: %v", err)
	}
	oldAPI, oldCommand := apiClient.Transport, commandClient.Transport
	apiClient.Transport = rewriteTransport{u}
	commandClient.Transport = rewriteTransport{u}
	t.Cleanup(func() {
		apiClient.Transport = oldAPI
		commandClient.Transport = oldCommand
	})
}

func TestFetchSatisfactoryAPI(t *testing.T) {
	fakeAPI(t, func(call apiRequest, w http.ResponseWriter) {
		switch call.Function {
		case "HealthCheck":
			w.Write([]byte(`{"data":{"health":"healthy"}}`))
		case "QueryServerState":
			if call.Auth != "Bearer tok" {
				t.Errorf("QueryServerState Authorization = %q, want %q", call.Auth, "Bearer tok")
			}
			w.Write([]byte(`{"data":{"serverGameState":{"activeSessionName":"Ficsit","numConnectedPlayers":2,"playerLimit":4,"techTier":6,"gamePhase":"Phase3","isGameRunning":true,"averageTickRate":29.5}}}`))
		default:
			t.Errorf("unexpected function %q", call.Function)
		}
	})

	info, err := fetchSatisfactoryAPI("factory.example", "tok")
	if err != nil {
		t.Fatalf("fetchSatisfactoryAPI: %v", err)
	}
	if !info.Healthy {
		t.Error("Healthy = false, want true")
	}
	if info.SessionName != "Ficsit" {
		t.Errorf("SessionName = %q, want %q", info.SessionName, "Ficsit")
	}
	if info.ConnectedPlayers != 2 || info.PlayerLimit != 4 {
		t.Errorf("players = %d/%d, want 2/4", info.ConnectedPlayers, info.PlayerLimit)
	}
	if info.TechTier != 6 || info.GamePhase != "Phase3" || info.AverageTickRate != 29.5 {
		t.Errorf("state = %+v, want tier 6 / Phase3 / 29.5 ticks", info)
	}
}

func TestCommand(t *testing.T) {
	fakeAPI(t, func(call apiRequest, w http.ResponseWriter) {
		switch call.Function {
		case "PasswordLogin":
			if call.Data["Password"] != "hunter2" {
				w.Write([]byte(`{"errorCode":"wrong_password","errorMessage":"Provided password did not match either Client or Admin passwords"}`))
				return
			}
			if call.Data["MinimumPrivilegeLevel"] != "Administrator" {
				t.Errorf("MinimumPrivilegeLevel = %q", call.Data["MinimumPrivilegeLevel"])
			}
			w.Write([]byte(`{"data":{"authenticationToken":"tok"}}`))
		case "RunCommand":
			w.Write([]byte(`{"data":{"commandResult":"Tick Rate: 30","returnValue":true}}`))
		default:
			t.Errorf("unexpected function %q", call.Function)
		}
	})

	svc := &Service{Host: "factory.example", AdminPassword: "hunter2"}
	out, err := svc.Command("  /FG.NetworkQuality  ")
	if err != nil {
		t.Fatalf("Command: %v", err)
	}
	if out != "Tick Rate: 30" {
		t.Errorf("Command output = %q, want %q", out, "Tick Rate: 30")
	}

	bad := &Service{Host: "factory.example", AdminPassword: "wrong"}
	if _, err := bad.Command("help"); err == nil || !strings.Contains(err.Error(), "did not match") {
		t.Errorf("wrong password error = %v, want one mentioning the API error message", err)
	}
}

// TestCommandPasswordlessRefused covers the live shape of every API failure:
// HTTP 200 with an errorCode/errorMessage body and no data field at all.
func TestCommandPasswordlessRefused(t *testing.T) {
	fakeAPI(t, func(call apiRequest, w http.ResponseWriter) {
		if call.Function != "PasswordlessLogin" {
			t.Errorf("unexpected function %q after a refused login", call.Function)
		}
		w.Write([]byte(`{"errorCode":"passwordless_login_not_possible","errorMessage":"Passwordless login is not possible in the current server configuration"}`))
	})

	svc := &Service{Host: "factory.example"}
	_, err := svc.Command("help")
	if err == nil || !strings.Contains(err.Error(), "Passwordless login is not possible") {
		t.Errorf("Command error = %v, want the API's errorMessage", err)
	}
}

func TestCommandPasswordlessFallback(t *testing.T) {
	fakeAPI(t, func(call apiRequest, w http.ResponseWriter) {
		switch call.Function {
		case "PasswordlessLogin":
			if _, ok := call.Data["Password"]; ok {
				t.Error("PasswordlessLogin sent a Password field")
			}
			w.Write([]byte(`{"data":{"authenticationToken":"tok"}}`))
		case "RunCommand":
			w.Write([]byte(`{"data":{"commandResult":"","returnValue":true}}`))
		default:
			t.Errorf("unexpected function %q", call.Function)
		}
	})

	svc := &Service{Host: "factory.example"}
	if _, err := svc.Command("help"); err != nil {
		t.Fatalf("Command: %v", err)
	}
}

func TestCommandRejectsBadInput(t *testing.T) {
	svc := &Service{Host: "factory.example"}
	cases := map[string]string{
		"empty":           "   ",
		"control char":    "say hi\nstop",
		"too long":        strings.Repeat("a", satisfactoryMaxCommand+1),
		"no host":         "help",
		"null byte":       "say hi\x00stop",
		"carriage return": "say hi\rstop",
	}
	for name, cmd := range cases {
		s := svc
		if name == "no host" {
			s = &Service{}
		}
		if _, err := s.Command(cmd); err == nil {
			t.Errorf("%s: expected an error", name)
		}
	}
}
