#!/usr/bin/env python3
"""Reverse-proxy orx for CANFAR contributed sessions.

orx serves a Vite SPA with absolute paths (``/assets/...``, ``/api/...``).
The browser URL is ``/session/contrib/<id>/`` while ingress strips that prefix
before the container. Absolute root paths therefore escape the session and the
UI stays blank (dark empty ``#root``).

This proxy:
  * listens on ``0.0.0.0:PUBLIC_PORT`` (default 5000)
  * forwards to ``127.0.0.1:ORX_PORT`` (default 4791)
  * rewrites HTML/JS/CSS so absolute ``/api``, ``/assets``, ``/favicon`` URLs
    include ``/session/contrib/<skaha_sessionid>``
"""

from __future__ import annotations

import os
import select
import socket
import sys
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


PUBLIC_PORT = int(os.environ.get("ASTROAI_OPENRESEARCH_PORT", "5000"))
ORX_HOST = os.environ.get("ORX_HOST", "127.0.0.1")
ORX_PORT = int(os.environ.get("ORX_PORT", "4791"))
SESSION_ID = (os.environ.get("skaha_sessionid") or "").strip()
PREFIX = f"/session/contrib/{SESSION_ID}" if SESSION_ID else ""

REWRITE_TYPES = (
    "text/html",
    "text/css",
    "text/javascript",
    "application/javascript",
    "application/x-javascript",
    "application/json",
)

# Absolute paths the SPA embeds that must stay under the contrib prefix.
ABS_PREFIXES = ("/api/", "/assets/", "/favicon")


def rewrite_body(data: bytes, content_type: str) -> bytes:
    if not PREFIX:
        return data
    ctype = content_type.split(";", 1)[0].strip().lower()
    if ctype not in REWRITE_TYPES and not ctype.endswith("+json"):
        return data
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    for abs_prefix in ABS_PREFIXES:
        # Avoid double-prefixing if somehow already rewritten.
        text = text.replace(f'"{PREFIX}{abs_prefix}', f'"__KEEP__{abs_prefix}')
        text = text.replace(f"'{PREFIX}{abs_prefix}", f"'__KEEP__{abs_prefix}")
        text = text.replace(f"`{PREFIX}{abs_prefix}", f"`__KEEP__{abs_prefix}")

        text = text.replace(f'"{abs_prefix}', f'"{PREFIX}{abs_prefix}')
        text = text.replace(f"'{abs_prefix}", f"'{PREFIX}{abs_prefix}")
        text = text.replace(f"`{abs_prefix}", f"`{PREFIX}{abs_prefix}")

        text = text.replace(f'"__KEEP__{abs_prefix}', f'"{PREFIX}{abs_prefix}')
        text = text.replace(f"'__KEEP__{abs_prefix}", f"'{PREFIX}{abs_prefix}")
        text = text.replace(f"`__KEEP__{abs_prefix}", f"`{PREFIX}{abs_prefix}")
    return text.encode("utf-8")


def rewrite_location(value: str) -> str:
    if not PREFIX or not value.startswith("/"):
        return value
    if value.startswith(PREFIX + "/") or value == PREFIX:
        return value
    for abs_prefix in ABS_PREFIXES:
        if value == abs_prefix.rstrip("/") or value.startswith(abs_prefix):
            return PREFIX + value
    if value.startswith("/api") or value.startswith("/assets"):
        return PREFIX + value
    return value


HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
    "host",
}


class OrxProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("orx-proxy: %s\n" % (fmt % args))

    def _proxy(self) -> None:
        # SSE / long-poll: stream without rewriting the body.
        accept = self.headers.get("Accept", "")
        streaming = "text/event-stream" in accept or self.path.startswith("/api/events")

        headers = {
            k: v
            for k, v in self.headers.items()
            if k.lower() not in HOP_BY_HOP
        }
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length > 0 else None

        conn = HTTPConnection(ORX_HOST, ORX_PORT, timeout=600)
        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            upstream = conn.getresponse()
        except OSError as exc:
            self.send_error(502, f"upstream orx unreachable: {exc}")
            return

        content_type = upstream.getheader("Content-Type") or ""
        raw = b"" if streaming else upstream.read()
        if not streaming:
            raw = rewrite_body(raw, content_type)

        self.send_response(upstream.status, upstream.reason)
        for key, value in upstream.getheaders():
            lk = key.lower()
            if lk in HOP_BY_HOP:
                continue
            if lk == "location":
                value = rewrite_location(value)
            if lk == "content-length" and not streaming:
                continue
            self.send_header(key, value)
        if not streaming:
            self.send_header("Content-Length", str(len(raw)))
        self.send_header("Connection", "close")
        self.end_headers()

        if streaming:
            try:
                while True:
                    chunk = upstream.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            try:
                self.wfile.write(raw)
            except (BrokenPipeError, ConnectionResetError):
                pass
        conn.close()

    def do_GET(self) -> None:  # noqa: N802
        self._proxy()

    def do_POST(self) -> None:  # noqa: N802
        self._proxy()

    def do_PUT(self) -> None:  # noqa: N802
        self._proxy()

    def do_PATCH(self) -> None:  # noqa: N802
        self._proxy()

    def do_DELETE(self) -> None:  # noqa: N802
        self._proxy()

    def do_HEAD(self) -> None:  # noqa: N802
        self._proxy()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._proxy()


def main() -> int:
    server = ThreadingHTTPServer(("0.0.0.0", PUBLIC_PORT), OrxProxyHandler)
    sys.stderr.write(
        f"orx-proxy: listening 0.0.0.0:{PUBLIC_PORT} → {ORX_HOST}:{ORX_PORT} "
        f"prefix={PREFIX or '(none)'}\n"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    # Unused imports kept for clarity if we later add raw WS tunneling.
    _ = (select, socket, urlsplit)
    raise SystemExit(main())
