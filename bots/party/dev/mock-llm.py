import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1])


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
        roles = [m["role"] for m in request["messages"]]
        turns = roles[1:] if roles[:1] == ["system"] else roles
        expected = ["user" if i % 2 == 0 else "assistant" for i in range(len(turns))]
        if not turns or turns != expected or turns[-1] != "user":
            print(f"refused roles {','.join(roles)}", flush=True)
            return self.reply(400, {"error": "Conversation roles must alternate user/assistant/user/assistant/..."})
        last = request["messages"][-1]["content"].splitlines()[-1]
        print(f"model {request.get('model')}: {len(turns)} turns, thinking {request.get('chat_template_kwargs')}", flush=True)
        content = f"(mock) I heard {last}"
        if "inject" in last:
            content = ":quit\n" + content
        self.reply(200, {"choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}]})

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(("", PORT), Handler).serve_forever()
