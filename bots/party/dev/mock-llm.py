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
        lines = request["messages"][-1]["content"].splitlines()
        schema = request.get("response_format", {}).get("json_schema", {}).get("schema")
        print(f"model {request.get('model')}: {len(turns)} turns, thinking {request.get('chat_template_kwargs')}, "
              f"replies for {schema['required'] if schema else 'a direct message'}", flush=True)

        def heard(line):
            return (":quit\n" if "inject" in line else "") + f"(mock) I heard {line}"

        if schema:
            replies = {}
            for nick in schema["required"]:
                said = [l for l in lines if l.startswith((nick + ": ", nick + " [", nick + " (", f"[{nick} "))]
                replies[nick] = {"why": "mock", "talking_to": "you", "reply": heard(" / ".join(said) or "nothing")}
            content = json.dumps(replies)
        else:
            content = heard(lines[-1])
        self.reply(200, {"choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}]})

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(("", PORT), Handler).serve_forever()
