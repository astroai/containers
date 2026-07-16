"""Reverse-proxy Ray Dashboard (127.0.0.1:8265) under /dashboard/.

CANFAR contributed sessions only expose port 5000. Ray's official Dashboard
stays bound to localhost; this module strips the /dashboard prefix and forwards
HTTP + WebSocket traffic so users get jobs/nodes/metrics without a custom UI.

Path handling follows Ray docs: strip the prefix and always use a trailing slash
when opening the UI (relative asset URLs).
"""

from __future__ import annotations

import asyncio
import os
from collections.abc import Iterable

import httpx
from fastapi import APIRouter, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import RedirectResponse, StreamingResponse
from starlette.background import BackgroundTask

DASHBOARD_PREFIX = "/dashboard"
_HOP_BY_HOP = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
        "host",
        "content-length",
    }
)


def dashboard_upstream() -> str:
    host = os.environ.get("RAY_DASHBOARD_HOST", "127.0.0.1").strip() or "127.0.0.1"
    port = os.environ.get("RAY_DASHBOARD_PORT", "8265").strip() or "8265"
    return f"http://{host}:{port}"


def dashboard_ws_upstream() -> str:
    return dashboard_upstream().replace("http://", "ws://", 1).replace("https://", "wss://", 1)


def dashboard_ready(timeout: float = 1.5) -> bool:
    try:
        with httpx.Client(timeout=timeout) as client:
            resp = client.get(f"{dashboard_upstream()}/")
            return resp.status_code < 500
    except (httpx.HTTPError, OSError):
        return False


def _filter_request_headers(headers: Iterable[tuple[str, str]]) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, value in headers:
        if key.lower() in _HOP_BY_HOP:
            continue
        out[key] = value
    return out


def _filter_response_headers(headers: httpx.Headers) -> dict[str, str]:
    out: dict[str, str] = {}
    for key, value in headers.items():
        if key.lower() in _HOP_BY_HOP:
            continue
        out[key] = value
    return out


def _upstream_path(path: str) -> str:
    if path in {DASHBOARD_PREFIX, f"{DASHBOARD_PREFIX}/"}:
        return "/"
    if path.startswith(f"{DASHBOARD_PREFIX}/"):
        return path[len(DASHBOARD_PREFIX) :] or "/"
    return path


router = APIRouter()


@router.get(DASHBOARD_PREFIX)
def dashboard_redirect() -> RedirectResponse:
    # Relative redirect keeps the browser under /session/contrib/<id>/ on CANFAR.
    return RedirectResponse(url="dashboard/", status_code=307)


@router.api_route(
    f"{DASHBOARD_PREFIX}/{{path:path}}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"],
)
async def proxy_dashboard_http(request: Request, path: str = "") -> Response:
    del path  # derived from request.url.path so /dashboard/ maps correctly
    upstream = dashboard_upstream()
    target_path = _upstream_path(request.url.path)
    url = httpx.URL(f"{upstream}{target_path}")
    if request.url.query:
        url = url.copy_with(query=request.url.query.encode("utf-8"))

    body = await request.body()
    headers = _filter_request_headers(request.headers.items())
    client = httpx.AsyncClient(timeout=None)

    try:
        upstream_req = client.build_request(
            request.method,
            url,
            headers=headers,
            content=body if body else None,
        )
        upstream_resp = await client.send(upstream_req, stream=True)
    except httpx.HTTPError as exc:
        await client.aclose()
        return Response(
            content=(
                "Ray Dashboard is not reachable yet. "
                "Wait for the Ray head to finish starting, then refresh.\n"
                f"Detail: {exc}\n"
            ),
            status_code=502,
            media_type="text/plain",
        )

    async def _cleanup() -> None:
        await upstream_resp.aclose()
        await client.aclose()

    return StreamingResponse(
        upstream_resp.aiter_raw(),
        status_code=upstream_resp.status_code,
        headers=_filter_response_headers(upstream_resp.headers),
        background=BackgroundTask(_cleanup),
    )


@router.websocket(f"{DASHBOARD_PREFIX}/{{path:path}}")
async def proxy_dashboard_ws(websocket: WebSocket, path: str = "") -> None:
    await websocket.accept()
    target_path = _upstream_path(f"{DASHBOARD_PREFIX}/{path}" if path else f"{DASHBOARD_PREFIX}/")
    query = websocket.scope.get("query_string", b"").decode("utf-8")
    url = f"{dashboard_ws_upstream()}{target_path}"
    if query:
        url = f"{url}?{query}"

    try:
        import websockets
    except ImportError:
        await websocket.close(code=1011, reason="websockets package missing")
        return

    try:
        async with websockets.connect(url, open_timeout=10) as upstream_ws:

            async def client_to_upstream() -> None:
                try:
                    while True:
                        message = await websocket.receive()
                        if message["type"] == "websocket.disconnect":
                            break
                        if message.get("text") is not None:
                            await upstream_ws.send(message["text"])
                        elif message.get("bytes") is not None:
                            await upstream_ws.send(message["bytes"])
                except WebSocketDisconnect:
                    pass

            async def upstream_to_client() -> None:
                try:
                    async for message in upstream_ws:
                        if isinstance(message, bytes):
                            await websocket.send_bytes(message)
                        else:
                            await websocket.send_text(str(message))
                except Exception:  # noqa: BLE001
                    pass

            tasks = [
                asyncio.create_task(client_to_upstream()),
                asyncio.create_task(upstream_to_client()),
            ]
            _done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in pending:
                task.cancel()
    except Exception:  # noqa: BLE001
        try:
            await websocket.close(code=1011)
        except Exception:  # noqa: BLE001
            pass
