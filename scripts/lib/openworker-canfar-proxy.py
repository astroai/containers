#!/usr/bin/env python3
"""Path-rewriting reverse proxy for OpenWorker on CANFAR contributed sessions.

Listens on ``0.0.0.0:5000`` and:
  * serves the built Vite UI from ``OPENWORKER_UI_ROOT``
  * proxies ``/v1/*`` and ``/ws/*`` to ``openworker-server`` (default :8765)
  * proxies ``/astroai-agents/*`` to the AstroAI agent wizard
  * injects ``window.__COWORKER_HTTP__`` / ``__COWORKER_WS__`` so the SPA
    talks through the contrib prefix (not hardcoded 127.0.0.1:8765)
"""

from __future__ import annotations

import mimetypes
import os
import select
import socket
import sys
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


PUBLIC_PORT = int(os.environ.get("ASTROAI_OPENWORKER_PORT", "5000"))
OW_HOST = os.environ.get("OPENWORKER_HOST", "127.0.0.1")
OW_PORT = int(os.environ.get("OPENWORKER_PORT", "8765"))
WIZARD_HOST = os.environ.get("ASTROAI_AGENT_WIZARD_HOST", "127.0.0.1")
WIZARD_PORT = int(os.environ.get("ASTROAI_AGENT_WIZARD_PORT", "4792"))
UI_ROOT = Path(os.environ.get("OPENWORKER_UI_ROOT", "/opt/openworker/gui")).resolve()
SESSION_ID = (os.environ.get("skaha_sessionid") or "").strip()
PREFIX = f"/session/contrib/{SESSION_ID}" if SESSION_ID else ""
WIZARD_MOUNT = "/astroai-agents"

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

AGENTS_CHIP = (
    '<a id="astroai-agents-chip" href="{href}" '
    'style="position:fixed;right:12px;bottom:12px;z-index:2147483646;'
    "padding:8px 12px;border-radius:8px;background:#1a2332;color:#e7ecf3;"
    "font:600 13px/1.2 system-ui,sans-serif;text-decoration:none;"
    'border:1px solid #2a3548;box-shadow:0 4px 16px rgba(0,0,0,.35)">'
    "Agents / Resources</a>"
)


def inject_index(html: bytes) -> bytes:
    try:
        text = html.decode("utf-8")
    except UnicodeDecodeError:
        return html
    # Prefer runtime globals so the SPA does not stick to baked 127.0.0.1:8765.
    # Empty PREFIX (local smoke): same-origin host root. CANFAR: contrib path prefix.
    # Use `|| location…` so an empty string does not fall through to Vite defaults
    # (JS treats "" as falsy in `a || b`).
    inject = (
        "<script>"
        f"window.__COWORKER_HTTP__={PREFIX!r}||(location.protocol+'//'+location.host);"
        "window.__COWORKER_WS__=(location.protocol==='https:'?'wss://':'ws://')"
        f"+location.host+({PREFIX!r}||'');"
        "</script>"
    )
    if "__COWORKER_HTTP__" not in text:
        lower = text.lower()
        idx = lower.find("<head>")
        if idx >= 0:
            insert_at = idx + len("<head>")
            text = text[:insert_at] + inject + text[insert_at:]
        else:
            text = inject + text
    if "astroai-agents-chip" not in text:
        href = f"{PREFIX}{WIZARD_MOUNT}/" if PREFIX else f"{WIZARD_MOUNT}/"
        chip = AGENTS_CHIP.format(href=href)
        lower = text.lower()
        idx = lower.rfind("</body>")
        if idx >= 0:
            text = text[:idx] + chip + text[idx:]
        else:
            text += chip
    return text.encode("utf-8")


def _forward_http(handler: BaseHTTPRequestHandler, host: str, port: int, path: str) -> None:
    headers = {
        k: v
        for k, v in handler.headers.items()
        if k.lower() not in HOP_BY_HOP
    }
    length = int(handler.headers.get("Content-Length", "0") or "0")
    body = handler.rfile.read(length) if length > 0 else None
    conn = HTTPConnection(host, port, timeout=600)
    try:
        conn.request(handler.command, path, body=body, headers=headers)
        upstream = conn.getresponse()
    except OSError as exc:
        if host == WIZARD_HOST and port == WIZARD_PORT:
            fallback = (
                b"<!DOCTYPE html><html><body style='font-family:sans-serif;padding:2rem'>"
                b"<h1>Agents unavailable</h1>"
                b"<p>Use webterm: <code>astroai-lab agent status</code></p>"
                b"</body></html>"
            )
            handler.send_response(503)
            handler.send_header("Content-Type", "text/html; charset=utf-8")
            handler.send_header("Content-Length", str(len(fallback)))
            handler.end_headers()
            try:
                handler.wfile.write(fallback)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        handler.send_error(502, f"upstream unreachable: {exc}")
        return

    raw = upstream.read()
    handler.send_response(upstream.status, upstream.reason)
    for key, value in upstream.getheaders():
        if key.lower() in HOP_BY_HOP:
            continue
        handler.send_header(key, value)
    handler.send_header("Content-Length", str(len(raw)))
    handler.send_header("Connection", "close")
    handler.end_headers()
    try:
        handler.wfile.write(raw)
    except (BrokenPipeError, ConnectionResetError):
        pass
    conn.close()


def _tunnel_websocket(handler: BaseHTTPRequestHandler, host: str, port: int, path: str) -> None:
    """Best-effort HTTP Upgrade tunnel for OpenWorker /ws/*."""
    try:
        upstream = socket.create_connection((host, port), timeout=30)
    except OSError as exc:
        handler.send_error(502, f"ws upstream unreachable: {exc}")
        return

    req_lines = [f"{handler.command} {path} HTTP/1.1", f"Host: {host}:{port}"]
    for key, value in handler.headers.items():
        if key.lower() == "host":
            continue
        req_lines.append(f"{key}: {value}")
    req_lines.append("")
    req_lines.append("")
    upstream.sendall("\r\n".join(req_lines).encode("latin-1"))

    # Read upstream handshake response and relay to client.
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = upstream.recv(4096)
        if not chunk:
            break
        buf += chunk
    header, _, rest = buf.partition(b"\r\n\r\n")
    try:
        handler.connection.sendall(header + b"\r\n\r\n" + rest)
    except OSError:
        upstream.close()
        return

    client = handler.connection
    try:
        while True:
            r, _, _ = select.select([client, upstream], [], [], 60)
            if not r:
                continue
            for sock in r:
                other = upstream if sock is client else client
                data = sock.recv(65536)
                if not data:
                    return
                other.sendall(data)
    except OSError:
        pass
    finally:
        try:
            upstream.close()
        except OSError:
            pass


def _serve_static(handler: BaseHTTPRequestHandler, url_path: str) -> None:
    path = urlsplit(url_path).path
    rel = unquote(path.lstrip("/")) or "index.html"
    candidate = (UI_ROOT / rel).resolve()
    try:
        candidate.relative_to(UI_ROOT)
    except ValueError:
        handler.send_error(403)
        return
    if candidate.is_dir():
        candidate = candidate / "index.html"
    if not candidate.is_file():
        # SPA fallback
        candidate = UI_ROOT / "index.html"
        if not candidate.is_file():
            handler.send_error(404, "OpenWorker UI not built")
            return
    data = candidate.read_bytes()
    ctype = mimetypes.guess_type(str(candidate))[0] or "application/octet-stream"
    if candidate.name == "index.html":
        data = inject_index(data)
        ctype = "text/html; charset=utf-8"
    handler.send_response(200)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "no-cache" if candidate.name == "index.html" else "public, max-age=3600")
    handler.end_headers()
    try:
        handler.wfile.write(data)
    except (BrokenPipeError, ConnectionResetError):
        pass


class OpenWorkerProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("openworker-proxy: %s\n" % (fmt % args))

    def _dispatch(self) -> None:
        path = self.path
        if path == WIZARD_MOUNT or path.startswith(WIZARD_MOUNT + "/"):
            rest = path[len(WIZARD_MOUNT) :] or "/"
            _forward_http(self, WIZARD_HOST, WIZARD_PORT, rest)
            return

        upgrade = (self.headers.get("Upgrade") or "").lower()
        if path.startswith("/ws/") or (upgrade == "websocket" and path.startswith("/ws")):
            _tunnel_websocket(self, OW_HOST, OW_PORT, path)
            return

        if path.startswith("/v1/") or path == "/v1":
            _forward_http(self, OW_HOST, OW_PORT, path)
            return

        _serve_static(self, path)

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch()

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch()

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch()

    def do_PATCH(self) -> None:  # noqa: N802
        self._dispatch()

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch()

    def do_HEAD(self) -> None:  # noqa: N802
        self._dispatch()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._dispatch()


def main() -> int:
    if not UI_ROOT.is_dir():
        sys.stderr.write(f"openworker-proxy: UI root missing: {UI_ROOT}\n")
    server = ThreadingHTTPServer(("0.0.0.0", PUBLIC_PORT), OpenWorkerProxyHandler)
    sys.stderr.write(
        f"openworker-proxy: 0.0.0.0:{PUBLIC_PORT} ui={UI_ROOT} "
        f"api={OW_HOST}:{OW_PORT} wizard={WIZARD_PORT} prefix={PREFIX or '(none)'}\n"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
