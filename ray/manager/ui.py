"""HTML helpers for the Ray manager contributed UI."""

from __future__ import annotations

import html
from urllib.parse import quote


def flash_html(flash: str | None, message: str | None) -> str:
    if not flash or not message:
        return ""
    safe = html.escape(message)
    css = {
        "ok": "background:#e6f4ea;color:#137333",
        "error": "background:#fce8e6;color:#c5221f",
        "warn": "background:#fef7e0;color:#b06000",
    }.get(flash, "background:#e8f0fe;color:#1967d2")
    return f'<p class="flash" style="{css};padding:0.6rem 1rem;border-radius:4px">{safe}</p>'


def redirect_with_flash(path: str, flash: str, message: str) -> str:
    return f"{path}?flash={quote(flash)}&msg={quote(message)}"


PAGE_STYLE = """
body { font-family: system-ui, sans-serif; max-width: 960px; margin: 1.5rem auto; padding: 0 1rem; }
h1 { font-size: 1.5rem; }
table { border-collapse: collapse; width: 100%; margin: 0.5rem 0 1rem; }
th, td { border: 1px solid #ccc; padding: 0.4rem 0.6rem; text-align: left; font-size: 0.9rem; }
code { background: #f4f4f4; padding: 0.1rem 0.3rem; border-radius: 3px; }
form.inline { display: inline; margin: 0; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 0.5rem; margin: 0.5rem 0 1rem; }
button { cursor: pointer; padding: 0.35rem 0.75rem; }
.actions form { display: inline-block; margin: 0 0.5rem 0.5rem 0; }
.status-ok { color: #137333; }
.status-bad { color: #c5221f; }
.status-warn { color: #b06000; }
"""
