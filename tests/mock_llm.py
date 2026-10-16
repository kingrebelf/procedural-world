#!/usr/bin/env python3
"""Fake language-model server for tests: speaks the OpenAI chat-completions format at
/v1/chat/completions, the Anthropic Messages format at /v1/messages, and the external
NPC decision contract at /decide. Usage: python3 tests/mock_llm.py [port]"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REPLY = {"say": "I am a mock villager.", "mood": "happy", "action": "none", "rel_change": 3,
         "remember": "mock memory: the traveller asked my name", "goal": "test the game",
         "options": ["Tell me more.", "Goodbye."]}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        req = json.loads(self.rfile.read(n) or b"{}")
        if self.path.endswith("/chat/completions"):
            if self.headers.get("Authorization") != "Bearer test-key":
                return self._send(401, {"error": {"message": "bad key"}})
            if req["messages"][0]["role"] != "system":
                return self._send(400, {"error": {"message": "system message missing"}})
            text = "```json\n" + json.dumps(REPLY) + "\n```"
            return self._send(200, {"choices": [{"message": {"role": "assistant", "content": text}}]})
        if self.path.endswith("/messages"):
            if self.headers.get("x-api-key") != "test-key" or self.headers.get("anthropic-version") != "2023-06-01":
                return self._send(401, {"type": "error", "error": {"type": "authentication_error", "message": "bad key"}})
            if not isinstance(req.get("system"), str) or req["messages"][0]["role"] != "user":
                return self._send(400, {"type": "error", "error": {"message": "bad request shape"}})
            return self._send(200, {"type": "message", "role": "assistant", "stop_reason": "end_turn",
                                    "content": [{"type": "thinking", "thinking": "..."},
                                                {"type": "text", "text": json.dumps(REPLY)}]})
        if self.path.endswith("/decide"):
            out = [{"id": n["id"], "action": "socialize", "seconds": 5} for n in req.get("npcs", [])]
            return self._send(200, {"decisions": out})
        self._send(404, {"error": "not found"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    HTTPServer(("127.0.0.1", port), H).serve_forever()
