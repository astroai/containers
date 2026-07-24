#!/usr/bin/env python3
"""AstroAI agent wizard sidecar — thin UI over ``astroai-lab agent`` CLI.

Listens on 127.0.0.1:ASTROAI_AGENT_WIZARD_PORT (default 4792).
Proxied as /astroai-agents/ by the session path-rewrite proxy.
Failures here must never affect the main UI process.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("ASTROAI_AGENT_WIZARD_PORT", "4792"))
CLI_TIMEOUT = int(os.environ.get("ASTROAI_AGENT_WIZARD_CLI_TIMEOUT", "600"))
HOME = Path.home()


def _run_lab(args: list[str], *, timeout: int | None = None) -> tuple[int, str, str]:
    cmd = ["astroai-lab", *args]
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout or CLI_TIMEOUT,
            env=os.environ.copy(),
        )
        return proc.returncode, proc.stdout or "", proc.stderr or ""
    except FileNotFoundError:
        return 127, "", "astroai-lab not found on PATH"
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {timeout or CLI_TIMEOUT}s"
    except OSError as exc:
        return 1, "", str(exc)


def _parse_json_stdout(stdout: str) -> object | None:
    text = stdout.strip()
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        # Rich / warnings may precede JSON — take last {...} block.
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(text[start : end + 1])
            except json.JSONDecodeError:
                return None
        return None


def _log_tail(n: int = 40) -> str:
    path = HOME / ".astroai" / "lab" / "agent-setup.log"
    if not path.is_file():
        return ""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    return "\n".join(lines[-n:])


CHEATSHEET = """\
# webterm (or any shell sharing /arc/home)
astroai-lab agent status
astroai-lab agent verify
astroai-lab --yes agent setup
astroai-lab agent install kilo
astroai-lab agent add --tag lean
less ~/.astroai/lab/agent-setup.log
"""

INDEX_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>AstroAI Agents</title>
<style>
  :root {
    --bg: #0f1419;
    --panel: #1a2332;
    --text: #e7ecf3;
    --muted: #8b9bb4;
    --accent: #3d8bfd;
    --ok: #3dd68c;
    --warn: #f5a524;
    --err: #f31260;
    --border: #2a3548;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
    background: radial-gradient(1200px 600px at 10% -10%, #1b2a44, var(--bg));
    color: var(--text); min-height: 100vh; padding: 1.5rem;
  }
  h1 { font-size: 1.6rem; font-weight: 600; margin: 0 0 .25rem; letter-spacing: -.02em; }
  .sub { color: var(--muted); margin-bottom: 1.25rem; max-width: 42rem; }
  .row { display: flex; flex-wrap: wrap; gap: .6rem; margin-bottom: 1rem; }
  button {
    background: var(--accent); color: #fff; border: 0; border-radius: 6px;
    padding: .55rem .9rem; font: inherit; cursor: pointer;
  }
  button.secondary { background: var(--panel); border: 1px solid var(--border); }
  button:disabled { opacity: .5; cursor: wait; }
  .grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); }
  section {
    background: color-mix(in srgb, var(--panel) 88%, transparent);
    border: 1px solid var(--border); border-radius: 10px; padding: 1rem;
  }
  h2 { font-size: .95rem; margin: 0 0 .75rem; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; }
  table { width: 100%; border-collapse: collapse; font-size: .9rem; }
  td, th { text-align: left; padding: .35rem .25rem; border-bottom: 1px solid var(--border); }
  .ok { color: var(--ok); } .bad { color: var(--err); } .warn { color: var(--warn); }
  pre {
    background: #0b1018; border: 1px solid var(--border); border-radius: 8px;
    padding: .75rem; overflow: auto; max-height: 220px; font-size: .78rem;
    color: #c5d0e0; white-space: pre-wrap;
  }
  #msg { min-height: 1.2rem; margin-bottom: .75rem; color: var(--muted); }
  a { color: var(--accent); }
</style>
</head>
<body>
  <h1>AstroAI Agents</h1>
  <p class="sub">Install coding CLIs and write agent configs on your shared home.
  The main session UI keeps running even if something here fails.</p>
  <div id="msg"></div>
  <div class="row">
    <button id="btn-refresh" class="secondary">Refresh</button>
    <button id="btn-setup">Core setup</button>
    <button id="btn-kilo" class="secondary">Install kilo</button>
    <button id="btn-lean" class="secondary">Lean addons</button>
    <button id="btn-models" class="secondary">Free models</button>
  </div>
  <div class="grid">
    <section>
      <h2>Session resources</h2>
      <div id="resources">Loading…</div>
    </section>
    <section>
      <h2>Setup state</h2>
      <div id="setup-state">Loading…</div>
    </section>
    <section>
      <h2>Agents</h2>
      <div id="agents">Loading…</div>
    </section>
    <section>
      <h2>Issues</h2>
      <div id="issues">Loading…</div>
    </section>
    <section>
      <h2>Escape hatch</h2>
      <pre id="cheat">""" + CHEATSHEET.replace("<", "&lt;") + """</pre>
      <p class="sub" style="margin:0">Prefer a shell? Use webterm with the same /arc home.</p>
    </section>
  </div>
  <section style="margin-top:1rem">
    <h2>Last log</h2>
    <pre id="log"></pre>
  </section>
<script>
const base = (document.querySelector('base') && document.querySelector('base').href) ||
  (location.pathname.replace(/\\/?$/, '/') );
async function api(path, opts) {
  const r = await fetch(base.replace(/\\/?$/, '/') + path.replace(/^\\//,''), opts);
  const text = await r.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { ok: false, error: text }; }
  return { status: r.status, data };
}
function setMsg(t, cls) {
  const el = document.getElementById('msg');
  el.textContent = t || '';
  el.className = cls || '';
}
function yn(v) { return v ? '<span class="ok">yes</span>' : '<span class="bad">no</span>'; }
function fmtPct(v) { return (v===null||v===undefined) ? '—' : (Math.round(v*10)/10) + '%'; }
function renderResources(r) {
  if (!r) return '<span class="warn">unavailable</span>';
  const home = r.home || {};
  const scratch = r.scratch || {};
  const gpus = r.gpu || [];
  let html = `<p>CPU ~${fmtPct(r.cpu_pct)} · RAM ${fmtPct(r.mem_pct)}` +
    (r.cgroup_mem_pct!=null ? ` · cgroup ${fmtPct(r.cgroup_mem_pct)}` : '') + `</p>`;
  html += `<p>Home ${fmtPct(home.pct)} <span class="sub">(${home.source||'?'})</span>` +
    ` · Scratch ${fmtPct(scratch.pct)}</p>`;
  if (gpus.length) {
    html += '<p>GPU: ' + gpus.map(g => `${g.name||'gpu'} ${fmtPct(g.util_pct)}`).join(', ') + '</p>';
  }
  for (const n of (r.notes||[])) html += `<p class="sub">${n}</p>`;
  return html;
}
async function refresh() {
  setMsg('Loading…');
  const { data } = await api('api/report');
  const setup = (data.setup || {});
  document.getElementById('resources').innerHTML = renderResources(data.resources);
  document.getElementById('setup-state').innerHTML =
    `<p>OK: ${yn(!!data.ok)} · needs retry: ${yn(!!setup.needs_retry)}</p>` +
    `<p>Stamp: <code>${setup.stamp || '(never)'}</code></p>` +
    (setup.failed ? `<p class="warn">Failed: ${setup.failed}</p>` : '');
  const rows = (data.agents || []).map(a =>
    `<tr><td>${a.agent}</td><td>${yn(a.binary)}</td><td>${yn(a.config)}</td></tr>`).join('');
  document.getElementById('agents').innerHTML =
    `<table><tr><th>Agent</th><th>Binary</th><th>Config</th></tr>${rows}</table>`;
  const issues = data.issues || [];
  document.getElementById('issues').innerHTML = issues.length
    ? `<ul>${issues.map(i => `<li class="warn">${i}</li>`).join('')}</ul>`
    : '<span class="ok">No verify issues</span>';
  document.getElementById('log').textContent = data.log_tail || '(empty)';
  setMsg('');
}
async function action(path, label) {
  document.querySelectorAll('button').forEach(b => b.disabled = true);
  setMsg(label + '…');
  try {
    const { data } = await api(path, { method: 'POST' });
    setMsg((data.ok ? 'OK: ' : 'Done with issues: ') + (data.summary || data.error || ''), data.ok ? 'ok' : 'warn');
  } catch (e) {
    setMsg(String(e), 'bad');
  }
  document.querySelectorAll('button').forEach(b => b.disabled = false);
  await refresh();
}
document.getElementById('btn-refresh').onclick = () => refresh();
document.getElementById('btn-setup').onclick = () => action('api/setup', 'Core setup');
document.getElementById('btn-kilo').onclick = () => action('api/install?tool=kilo', 'Install kilo');
document.getElementById('btn-lean').onclick = () => action('api/add?tag=lean', 'Lean addons');
document.getElementById('btn-models').onclick = () => action('api/models-free', 'Free models');
refresh();
setInterval(refresh, 30000);
</script>
</body>
</html>
"""


FALLBACK_HTML = """<!DOCTYPE html>
<html><head><meta charset="utf-8"/><title>AstroAI Agents</title></head>
<body style="font-family:sans-serif;padding:2rem;background:#111;color:#eee">
<h1>Agents unavailable</h1>
<p>Use webterm (same /arc home) and run:</p>
<pre style="background:#222;padding:1rem">""" + CHEATSHEET + """</pre>
</body></html>
"""


class WizardHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("agent-wizard: %s\n" % (fmt % args))

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _json(self, code: int, payload: dict) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self._send(code, raw, "application/json; charset=utf-8")

    def _path(self) -> tuple[str, dict[str, list[str]]]:
        parsed = urlparse(self.path)
        # Accept both / and /astroai-agents/ when called directly or via strip.
        path = parsed.path
        for prefix in ("/astroai-agents",):
            if path.startswith(prefix):
                path = path[len(prefix) :] or "/"
        return path, parse_qs(parsed.query)

    def do_GET(self) -> None:  # noqa: N802
        path, _qs = self._path()
        if path in ("/", "/index.html"):
            self._send(200, INDEX_HTML.encode("utf-8"), "text/html; charset=utf-8")
            return
        if path == "/api/report":
            rc, out, err = _run_lab(["agent", "report"], timeout=120)
            data = _parse_json_stdout(out)
            if isinstance(data, dict):
                data.setdefault("log_tail", _log_tail())
                data["cli_exit"] = rc
                if err and not data.get("ok"):
                    data.setdefault("cli_stderr", err[-2000:])
                self._json(200 if rc in (0, 1) else 500, data)
                return
            self._json(
                500,
                {
                    "ok": False,
                    "error": err or out or "report failed",
                    "log_tail": _log_tail(),
                    "cli_exit": rc,
                },
            )
            return
        if path == "/healthz":
            self._json(200, {"ok": True})
            return
        self._send(404, b"not found\n", "text/plain; charset=utf-8")

    def do_POST(self) -> None:  # noqa: N802
        path, qs = self._path()
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length:
            self.rfile.read(length)

        try:
            if path == "/api/setup":
                rc, out, err = _run_lab(["--yes", "--json", "agent", "setup"])
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["partial"] = rc == 2
                data["cli_exit"] = rc
                data["summary"] = (
                    "setup ok"
                    if rc == 0
                    else ("partial setup" if rc == 2 else (err or out or "setup failed")[:300])
                )
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/install":
                tool = (qs.get("tool") or ["kilo"])[0]
                rc, out, err = _run_lab(["--json", "agent", "install", tool])
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["cli_exit"] = rc
                data["summary"] = f"install {tool}" if rc == 0 else (err or out or "failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/add":
                tag = (qs.get("tag") or [None])[0]
                name = (qs.get("name") or [None])[0]
                args = ["--yes", "--json", "agent", "add"]
                if tag:
                    args.extend(["--tag", tag])
                elif name:
                    args.append(name)
                else:
                    args.extend(["--tag", "lean"])
                rc, out, err = _run_lab(args)
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["partial"] = rc == 2
                data["cli_exit"] = rc
                data["summary"] = "addons ok" if rc == 0 else (err or out or "failed")[:300]
                data["log_tail"] = _log_tail()
                self._json(200, data)
                return

            if path == "/api/models-free":
                rc, out, err = _run_lab(["--yes", "--json", "agent", "models", "free"])
                data = _parse_json_stdout(out) or {}
                if not isinstance(data, dict):
                    data = {}
                data["ok"] = rc == 0
                data["cli_exit"] = rc
                data["summary"] = "models applied" if rc == 0 else (err or out or "failed")[:300]
                self._json(200, data)
                return

            self._send(404, b"not found\n", "text/plain; charset=utf-8")
        except Exception as exc:  # noqa: BLE001 — never crash the server loop
            self._json(
                500,
                {
                    "ok": False,
                    "error": str(exc),
                    "trace": traceback.format_exc()[-1500:],
                    "log_tail": _log_tail(),
                },
            )


def main() -> int:
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PORT), WizardHandler)
    except OSError as exc:
        sys.stderr.write(f"agent-wizard: bind failed: {exc}\n")
        return 1
    sys.stderr.write(f"agent-wizard: listening 127.0.0.1:{PORT}\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
