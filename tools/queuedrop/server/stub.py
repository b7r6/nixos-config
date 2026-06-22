#!/usr/bin/env python3
"""
queuedrop stub server — the queue endpoint the browser extension targets.

Contract (stable; the real backend will preserve it):
  POST /queue
    headers: Content-Type: application/json
             Authorization: Bearer <token>      (optional; if QUEUEDROP_TOKEN set)
    body:    {"url": "<source/playlist/track url>"}
    200:     {"ok": true,  "id": <int>, "title": "<resolved name>", "url": "<url>"}
    4xx:     {"ok": false, "error": "<message>"}

  GET /healthz -> {"ok": true}

CORS: permissive (the extension calls cross-origin from background/service-worker;
preflight must succeed). Tailnet-only exposure is the trust boundary.

This stub just ECHOES/accepts the URL (records it to a jsonl log) so the
extension can be developed end-to-end before the real Pinchflat-backed handler
(which will call `Sources.create_source` via `bin/pinchflat rpc`) is wired in.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


TOKEN = os.environ.get("QUEUEDROP_TOKEN", "")
LOG = os.environ.get("QUEUEDROP_LOG", os.path.expanduser("~/src/queuedrop/server/queue.jsonl"))


def _cors(h: BaseHTTPRequestHandler) -> None:
  h.send_header("Access-Control-Allow-Origin", "*")
  h.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
  h.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")


class Handler(BaseHTTPRequestHandler):
  def _json(self, code: int, payload: dict) -> None:
    body = json.dumps(payload).encode()
    self.send_response(code)
    self.send_header("Content-Type", "application/json")
    _cors(self)
    self.send_header("Content-Length", str(len(body)))
    self.end_headers()
    self.wfile.write(body)

  def do_OPTIONS(self) -> None:  # CORS preflight
    self.send_response(204)
    _cors(self)
    self.end_headers()

  def do_GET(self) -> None:
    if self.path == "/healthz":
      self._json(200, {"ok": True})
    else:
      self._json(404, {"ok": False, "error": "not found"})

  def do_POST(self) -> None:
    if self.path != "/queue":
      return self._json(404, {"ok": False, "error": "not found"})

    if TOKEN:
      auth = self.headers.get("Authorization", "")
      if auth != f"Bearer {TOKEN}":
        return self._json(401, {"ok": False, "error": "unauthorized"})

    try:
      n = int(self.headers.get("Content-Length", "0"))
      data = json.loads(self.rfile.read(n) or b"{}")
    except (ValueError, json.JSONDecodeError):
      return self._json(400, {"ok": False, "error": "invalid json"})

    url = (data.get("url") or "").strip()
    if not url.startswith(("http://", "https://")):
      return self._json(400, {"ok": False, "error": "missing/invalid url"})

    rec = {"ts": datetime.now(timezone.utc).isoformat(), "url": url}
    with open(LOG, "a", encoding="utf-8") as f:
      f.write(json.dumps(rec) + "\n")

    # Stub: pretend we enqueued it. The real handler returns the Pinchflat
    # source id + resolved collection title here.
    title = url.rstrip("/").rsplit("/", 1)[-1].replace("-", " ").title()
    print(f"[queued] {url}", file=sys.stderr)
    self._json(200, {"ok": True, "id": 0, "title": title, "url": url})

  def log_message(self, format, *args):
    pass


def main() -> int:
  host = os.environ.get("QUEUEDROP_HOST", "127.0.0.1")
  port = int(os.environ.get("QUEUEDROP_PORT", "8946"))
  srv = ThreadingHTTPServer((host, port), Handler)
  print(f"queuedrop stub on http://{host}:{port}  (log: {LOG})", file=sys.stderr)
  try:
    srv.serve_forever()
  except KeyboardInterrupt:
    pass
  return 0


if __name__ == "__main__":
  sys.exit(main())
