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
        content = request["messages"][-1]["content"]
        lines = content.splitlines()
        schema = request.get("response_format", {}).get("json_schema", {}).get("schema")
        branches = schema.get("anyOf", []) if schema else []
        answer = branches[-1] if branches else schema
        kind = "a judge's choice" if schema and "enum" in schema else \
            f"replies for {answer['properties']['replies']['required']}" if answer and "replies" in answer.get("properties", {}) else "a direct message"
        print(f"model {request.get('model')}: {len(turns)} turns, thinking {request.get('chat_template_kwargs')}, {kind}"
              + (", tools offered" if branches else ""), flush=True)

        def heard(line):
            return (":quit\n" if "inject" in line else "") + f"(mock) I heard {line}"

        said = content.split("\n\n[", 1)[0].lower()
        found = [l[2:] for l in lines if l.startswith("- ")]
        if schema and "enum" in schema:
            options = schema["enum"]
            out = json.dumps("finished" if "finished" in options else "chill" if "chill" in options else options[0])
        elif branches and "[tool results" not in content and any(w in said for w in ("time", "note", "draw")):
            print("  calling tools", flush=True)
            calls = []
            if "time" in said:
                calls.append({"tool": "time", "zone": "Europe/London"})
            if "note" in said:
                calls.append({"tool": "note", "text": "someone asked me to note something"})
            if "draw" in said:
                calls.append({"tool": "draw", "pose": "wave", "face": "happy", "caption": "hi from the mock"})
            out = json.dumps({"need": "mock", "tools": calls})
        else:
            body = {"need": "nothing", "tools": []} if branches else {}
            if "replies" in answer.get("properties", {}):
                replies = {}
                for nick, field in answer["properties"]["replies"]["properties"].items():
                    who = [l for l in lines if l.startswith((nick + ": ", nick + " [", nick + " (", f"[{nick} "))]
                    talking = field.get("properties", {}).get("talking_to", {}).get("const", "you")
                    reply = heard(" / ".join(who) or "nothing") + (f" and found {' / '.join(found)}" if found else "")
                    replies[nick] = {"why": "mock", "talking_to": talking, "reply": reply}
                body["replies"] = replies
            else:
                body["reply"] = heard(lines[0] if lines else "nothing") + (f" and found {' / '.join(found)}" if found else "")
            out = json.dumps(body)
        content = out
        self.reply(200, {"choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}]})

    def log_message(self, fmt, *args):
        pass


ThreadingHTTPServer(("", PORT), Handler).serve_forever()
