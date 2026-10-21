import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

COOKIE = "authelia_session"
USER = {"display_name": "Finlay", "emails": ["a@vin.moe"], "method": "totp", "has_totp": True, "has_webauthn": True, "has_duo": False}
CONFIG = {"available_methods": ["totp", "webauthn"], "password_change_disabled": False}
TOTP = {"created_at": "2026-08-20T10:00:00Z", "issuer": "vinnel.cloud", "algorithm": "SHA1", "digits": 6, "period": 30}
KEYS = [
    {"id": 1, "description": "YubiKey 5C", "created_at": "2026-08-21T10:00:00Z", "last_used_at": "2026-10-20T19:00:00Z", "attachment": "cross-platform"},
    {"id": 2, "description": "Laptop passkey", "created_at": "2026-09-02T10:00:00Z", "last_used_at": None, "attachment": "platform"},
]
SIGNED_IN = {"/api/user/info", "/api/configuration", "/api/secondfactor/totp", "/api/secondfactor/webauthn/credentials"}


class Handler(BaseHTTPRequestHandler):
    def level(self):
        for part in (self.headers.get("Cookie") or "").split(";"):
            name, _, value = part.strip().partition("=")
            if name == COOKIE and value in ("1", "2"):
                return int(value)
        return 0

    def reply(self, data, status=200, level=None):
        body = json.dumps({"status": "OK" if status == 200 else "KO", "data": data}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if level is not None:
            self.send_header("Set-Cookie", f"{COOKIE}={level}; Path=/; HttpOnly; SameSite=Lax")
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return {}

    def handle_api(self):
        path = urlparse(self.path).path
        payload = self.body() if self.command in ("POST", "PUT") else {}
        level = self.level()
        if path == "/api/state":
            return self.reply({"username": "finlay" if level else "", "authentication_level": level})
        if path == "/api/firstfactor":
            if not payload.get("username") or not payload.get("password"):
                return self.reply({"message": "Authentication failed."}, 401)
            return self.reply({}, level=1)
        if path == "/api/secondfactor/totp" and self.command == "POST":
            if level < 1 or not str(payload.get("token", "")).isdigit():
                return self.reply({"message": "Authentication failed."}, 401)
            return self.reply({}, level=2)
        if path == "/api/logout":
            return self.reply({}, level=0)
        if path in SIGNED_IN and level < 2:
            return self.reply({"message": "Unauthorized"}, 401)
        if path == "/api/user/info":
            return self.reply(USER)
        if path == "/api/configuration":
            return self.reply(CONFIG)
        if path == "/api/secondfactor/totp":
            return self.reply(TOTP)
        if path == "/api/secondfactor/webauthn/credentials":
            return self.reply(KEYS)
        return self.reply({})

    do_GET = do_POST = do_PUT = do_DELETE = handle_api

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(("0.0.0.0", int(sys.argv[1])), Handler).serve_forever()
