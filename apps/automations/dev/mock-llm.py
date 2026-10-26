import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1])
VALUES = "hestia/platform/helm-values/loki/values.yaml"

BREAKING = {
    "verdict": "breaking",
    "summary": "The chart renames singleBinary.persistence.storageClass, which the Loki values file still sets.",
    "findings": [
        {
            "severity": "breaking",
            "detail": "singleBinary.persistence.storageClass becomes storageClassName and the old key is ignored, so the volume would move off local-path-hostpath.",
            "file": VALUES,
        },
        {
            "severity": "warning",
            "detail": "loki.analytics moves to loki.usageStats, so reporting_enabled: false would stop applying and usage reports would be sent.",
            "file": VALUES,
        },
    ],
}

SAFE = {"verdict": "safe", "summary": "Nothing in the notes touches this configuration.", "findings": []}


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        if self.path != "/v1/chat/completions":
            return self.reply(404, {"error": "not found"})
        request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if request.get("response_format", {}).get("type") != "json_schema":
            return self.reply(400, {"error": "response_format json_schema expected"})
        prompt = request["messages"][-1]["content"]
        print(f"model {request.get('model')}: {len(prompt)}-byte prompt", flush=True)
        verdict = BREAKING if "BREAKING" in prompt and "storageClass:" in prompt else SAFE
        self.reply(200, {"choices": [{"index": 0, "message": {"role": "assistant", "content": json.dumps(verdict)}, "finish_reason": "stop"}]})

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(("", PORT), Handler).serve_forever()
