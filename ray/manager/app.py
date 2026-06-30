"""CANFAR Ray Manager web app — cluster lifecycle (Milestone C)."""

from __future__ import annotations

import os
import subprocess
from dataclasses import asdict
from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI, Form, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse, RedirectResponse
from pydantic import BaseModel, Field

from background_tasks import active_operation, start_background
from canfar_ops import CanfarOps
from cluster import (
    ClusterCreateRequest,
    clean_orphaned_workers,
    create_cluster,
    retry_worker,
    stop_cluster,
    validate_cluster_create,
)
from preflight import run_preflight
from ray_cluster import count_live_nodes, list_ray_nodes, ray_address, ray_running
from reconcile import reconcile_cluster
from settings import ManagerSettings, manager_pod_ip
from state_store import StateStore
from ui import PAGE_STYLE, flash_html, redirect_with_flash
from workers import destroy_all_workers, destroy_worker, launch_worker
from worker_logs import archive_session_logs, read_worker_logs

app = FastAPI(title="CANFAR Ray Manager")

_ray_head_proc: subprocess.Popen[str] | None = None
_settings = ManagerSettings.from_env()
_store = StateStore(_settings.cluster_id)
_canfar = CanfarOps()


def _heartbeat_path() -> Path:
    return _store.dir / "manager-heartbeat"


def _touch_heartbeat() -> None:
    path = _heartbeat_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()


class WorkerLaunchRequest(BaseModel):
    cores: int = Field(default=1, ge=1, le=32)
    ram_gb: int = Field(default=4, ge=1, le=128)
    gpus: int = Field(default=0, ge=0, le=8)
    require_preflight: bool = True


class ClusterCreateBody(BaseModel):
    name: str = Field(default="", max_length=64)
    worker_count: int = Field(default=2, ge=1, le=16)
    cores: int = Field(default=1, ge=1, le=32)
    ram_gb: int = Field(default=4, ge=1, le=128)
    gpus: int = Field(default=0, ge=0, le=8)
    min_joined: int | None = Field(default=None, ge=1, le=16)
    partial_policy: Literal["fail_and_cleanup", "accept_partial", "continue_waiting"] = "accept_partial"
    require_preflight: bool = True


@app.on_event("startup")
def startup() -> None:
    global _ray_head_proc
    _store.ensure_dir()
    if not ray_running():
        _ray_head_proc = subprocess.Popen(
            ["/opt/astroai/bin/ray-head-start.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
    state = _store.load()
    if state and state.phase not in {"Stopped", "Failed", "Idle"}:
        reconcile_cluster(canfar=_canfar, store=_store, state=state)


@app.get("/healthz")
def healthz() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/readyz")
def readyz() -> JSONResponse:
    scratch = Path(os.environ.get("TMP_SCRATCH_DIR", "/scratch"))
    if not scratch.is_dir() or not os.access(scratch, os.W_OK):
        return JSONResponse({"ready": False, "reason": "scratch unavailable"}, status_code=503)
    if not ray_running():
        return JSONResponse({"ready": False, "reason": "ray head unavailable"}, status_code=503)
    return JSONResponse({"ready": True, "ray_address": ray_address()})


@app.get("/api/v1/auth/status")
def api_auth_status() -> JSONResponse:
    return JSONResponse(asdict(_canfar.auth_status()))


@app.get("/api/v1/status")
def api_status() -> JSONResponse:
    _touch_heartbeat()
    state = reconcile_cluster(canfar=_canfar, store=_store)
    return JSONResponse(_cluster_payload(state))


@app.post("/api/v1/cluster/reconcile")
def api_cluster_reconcile() -> JSONResponse:
    state = reconcile_cluster(canfar=_canfar, store=_store)
    return JSONResponse(_cluster_payload(state))


def _cluster_create_request(body: ClusterCreateBody) -> ClusterCreateRequest:
    return ClusterCreateRequest(
        name=body.name or _settings.cluster_id,
        worker_count=body.worker_count,
        cores=body.cores,
        ram_gb=body.ram_gb,
        gpus=body.gpus,
        min_joined=body.min_joined,
        partial_policy=body.partial_policy,
        require_preflight=body.require_preflight,
    )


def _start_cluster_create(req: ClusterCreateRequest) -> None:
    create_cluster(
        settings=_settings,
        canfar=_canfar,
        store=_store,
        heartbeat_path=str(_heartbeat_path()),
        req=req,
    )


@app.post("/api/v1/preflight/run")
def api_preflight_run(async_mode: bool = Query(default=False, alias="async")) -> JSONResponse:
    _touch_heartbeat()
    if async_mode:
        op = active_operation()
        if op and op.running:
            raise HTTPException(status_code=409, detail=f"Operation in progress: {op.kind}")
        if not start_background("preflight", lambda: run_preflight(_settings, _canfar, _store)):
            raise HTTPException(status_code=409, detail="Operation already in progress")
        payload = _cluster_payload(_store.load())
        payload["accepted"] = True
        return JSONResponse(payload, status_code=202)

    report = run_preflight(_settings, _canfar, _store)
    code = 200 if report.passed else 503
    return JSONResponse(report.as_dict(), status_code=code)


@app.post("/api/v1/cluster/create")
def api_cluster_create(
    body: ClusterCreateBody,
    async_mode: bool = Query(default=False, alias="async"),
) -> JSONResponse:
    _touch_heartbeat()
    req = _cluster_create_request(body)
    try:
        validate_cluster_create(canfar=_canfar, store=_store, req=req)
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    if async_mode:
        op = active_operation()
        if op and op.running:
            raise HTTPException(status_code=409, detail=f"Operation in progress: {op.kind}")
        if not start_background("cluster_create", lambda: _start_cluster_create(req)):
            raise HTTPException(status_code=409, detail="Operation already in progress")
        payload = _cluster_payload(_store.load())
        payload["accepted"] = True
        return JSONResponse(payload, status_code=202)

    try:
        result = create_cluster(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
            req=req,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    payload = _cluster_payload(result.state)
    payload["success"] = result.success
    payload["message"] = result.message
    code = 200 if result.success else 503
    return JSONResponse(payload, status_code=code)


@app.post("/api/v1/cluster/stop")
def api_cluster_stop() -> JSONResponse:
    state = stop_cluster(canfar=_canfar, store=_store)
    return JSONResponse(_cluster_payload(state))


@app.post("/api/v1/cluster/clean-orphans")
def api_cluster_clean_orphans() -> JSONResponse:
    destroyed = clean_orphaned_workers(settings=_settings, canfar=_canfar, store=_store)
    return JSONResponse({"destroyed": destroyed})


@app.post("/api/v1/workers/launch")
def api_workers_launch(body: WorkerLaunchRequest) -> JSONResponse:
    _touch_heartbeat()
    try:
        result = launch_worker(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
            cores=body.cores,
            ram_gb=body.ram_gb,
            gpus=body.gpus,
            require_preflight=body.require_preflight,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    payload: dict[str, Any] = {"worker": asdict(result.worker)}
    if result.logs_excerpt:
        payload["logs_excerpt"] = result.logs_excerpt
    code = 200 if result.worker.ray_joined else 503
    return JSONResponse(payload, status_code=code)


@app.post("/api/v1/workers/{session_id}/retry")
def api_workers_retry(session_id: str) -> JSONResponse:
    try:
        worker = retry_worker(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
            session_id=session_id,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    code = 200 if worker.ray_joined else 503
    return JSONResponse({"worker": asdict(worker)}, status_code=code)


@app.get("/api/v1/workers/{session_id}/logs")
def api_worker_logs(session_id: str, refresh: bool = Query(default=False)) -> PlainTextResponse:
    if refresh:
        state = _store.load()
        worker = next((w for w in state.workers if w.session_id == session_id), None) if state else None
        archive_session_logs(
            canfar=_canfar,
            store=_store,
            session_id=session_id,
            worker=worker,
            state=state,
        )
    text = read_worker_logs(_store, session_id)
    if text is None:
        raise HTTPException(status_code=404, detail="No saved logs for this worker session")
    return PlainTextResponse(text)


@app.delete("/api/v1/workers/{session_id}")
def api_workers_destroy(session_id: str) -> JSONResponse:
    return JSONResponse(destroy_worker(canfar=_canfar, store=_store, session_id=session_id))


@app.post("/api/v1/workers/destroy-all")
def api_workers_destroy_all() -> JSONResponse:
    results = destroy_all_workers(canfar=_canfar, store=_store)
    return JSONResponse({"destroyed": results})


@app.get("/api/v1/ray/nodes")
def api_ray_nodes() -> JSONResponse:
    nodes = list_ray_nodes()
    return JSONResponse({"nodes": nodes, "alive": count_live_nodes(nodes=nodes)})


@app.post("/actions/preflight")
def action_preflight() -> RedirectResponse:
    op = active_operation()
    if op and op.running:
        return RedirectResponse(
            redirect_with_flash("/", "warn", f"Already running: {op.kind}"),
            status_code=303,
        )
    if not start_background("preflight", lambda: run_preflight(_settings, _canfar, _store)):
        return RedirectResponse(
            redirect_with_flash("/", "warn", "Could not start preflight"),
            status_code=303,
        )
    return RedirectResponse(
        redirect_with_flash("/", "ok", "Network preflight started — refresh for results"),
        status_code=303,
    )


@app.post("/actions/create-cluster")
def action_create_cluster(
    worker_count: int = Form(2),
    cores: int = Form(1),
    ram_gb: int = Form(4),
    gpus: int = Form(0),
    min_joined: int = Form(2),
    partial_policy: str = Form("accept_partial"),
) -> RedirectResponse:
    req = ClusterCreateRequest(
        name=_settings.cluster_id,
        worker_count=worker_count,
        cores=cores,
        ram_gb=ram_gb,
        gpus=gpus,
        min_joined=min_joined,
        partial_policy=partial_policy,  # type: ignore[arg-type]
        require_preflight=True,
    )
    try:
        validate_cluster_create(canfar=_canfar, store=_store, req=req)
    except RuntimeError as exc:
        return RedirectResponse(redirect_with_flash("/", "error", str(exc)), status_code=303)

    op = active_operation()
    if op and op.running:
        return RedirectResponse(
            redirect_with_flash("/", "warn", f"Already running: {op.kind}"),
            status_code=303,
        )
    if not start_background("cluster_create", lambda: _start_cluster_create(req)):
        return RedirectResponse(
            redirect_with_flash("/", "warn", "Could not start cluster create"),
            status_code=303,
        )
    return RedirectResponse(
        redirect_with_flash("/", "ok", "Cluster create started — refresh for progress"),
        status_code=303,
    )


@app.post("/actions/stop-cluster")
def action_stop_cluster() -> RedirectResponse:
    stop_cluster(canfar=_canfar, store=_store)
    return RedirectResponse(redirect_with_flash("/", "ok", "Cluster stopped"), status_code=303)


@app.post("/actions/reconcile")
def action_reconcile() -> RedirectResponse:
    state = reconcile_cluster(canfar=_canfar, store=_store)
    joined = len(_store.joined_workers(state)) if state else 0
    return RedirectResponse(
        redirect_with_flash("/", "ok", f"Reconciled — {joined} worker(s) joined"),
        status_code=303,
    )


@app.post("/actions/clean-orphans")
def action_clean_orphans() -> RedirectResponse:
    try:
        destroyed = clean_orphaned_workers(settings=_settings, canfar=_canfar, store=_store)
    except RuntimeError as exc:
        return RedirectResponse(redirect_with_flash("/", "error", str(exc)), status_code=303)
    return RedirectResponse(
        redirect_with_flash("/", "ok", f"Cleaned {len(destroyed)} orphaned session(s)"),
        status_code=303,
    )


@app.post("/actions/retry-worker/{session_id}")
def action_retry_worker(session_id: str) -> RedirectResponse:
    try:
        worker = retry_worker(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
            session_id=session_id,
        )
    except RuntimeError as exc:
        return RedirectResponse(redirect_with_flash("/", "error", str(exc)), status_code=303)
    msg = f"Retry {worker.name}: {'joined' if worker.ray_joined else worker.phase}"
    flash = "ok" if worker.ray_joined else "warn"
    return RedirectResponse(redirect_with_flash("/", flash, msg), status_code=303)


@app.get("/", response_class=HTMLResponse)
def index(request: Request) -> str:
    _touch_heartbeat()
    auth = _canfar.auth_status()
    state = reconcile_cluster(canfar=_canfar, store=_store)
    preflight = (state.preflight if state else None) or {}
    flash = request.query_params.get("flash")
    flash_msg = request.query_params.get("msg")

    workers_html = ""
    if state and state.workers:
        rows = []
        for w in state.workers:
            retry = ""
            if w.phase in {"CANFAR Failed", "Ray Unhealthy", "Orphaned"}:
                retry = (
                    f'<form class="inline" method="post" '
                    f'action="/actions/retry-worker/{w.session_id}">'
                    f'<button type="submit">Retry</button></form>'
                )
            logs_link = ""
            if w.logs_path or _store.worker_log_file(w.session_id).is_file():
                logs_link = (
                    f' <a href="/api/v1/workers/{w.session_id}/logs" target="_blank">logs</a>'
                )
            rows.append(
                f"<tr><td>{w.name}</td><td><code>{w.session_id}</code></td>"
                f"<td>{w.phase}</td><td>{w.canfar_status or '—'}</td>"
                f"<td>{w.worker_ip or '—'}</td>"
                f"<td>{'yes' if w.ray_joined else 'no'}</td>"
                f"<td>{w.last_error or ''}{logs_link} {retry}</td></tr>"
            )
        workers_html = (
            "<table><tr><th>Name</th><th>Session</th><th>Phase</th><th>CANFAR</th>"
            "<th>IP</th><th>Ray</th><th>Notes</th></tr>"
            + "".join(rows)
            + "</table>"
        )

    auth_line = (
        f'<span class="status-ok">Authenticated ({auth.idp})</span>'
        if auth.authenticated
        else (
            '<span class="status-bad">Not authenticated</span> — '
            "run <code>canfar auth login</code> in an AstroAI <strong>webterm</strong> or "
            "<strong>vscode</strong> session first (credentials persist on <code>/arc/home</code>), "
            "then refresh this page."
        )
    )
    pf_line = (
        f'<span class="status-ok">Passed</span> (probe worker {preflight.get("worker_ip", "?")})'
        if preflight.get("passed")
        else '<span class="status-warn">Not run or failed</span> — run preflight before creating a cluster'
    )
    cluster_phase = state.phase if state else "Idle"
    joined = len(_store.joined_workers(state)) if state else 0
    target = state.worker_count if state else 0

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>CANFAR Ray Manager</title>
<style>{PAGE_STYLE}</style></head>
<body>
  <h1>CANFAR Ray Manager</h1>
  {flash_html(flash, flash_msg)}
  <p>Ray: <code>{ray_address()}</code> · cluster <code>{_settings.cluster_id}</code></p>
  <p>Cluster phase: <strong>{cluster_phase}</strong> · workers joined: {joined}/{target or '—'}</p>
  <p>CANFAR auth: {auth_line}</p>
  <p>Network preflight: {pf_line}</p>
  <p>Live Ray nodes: {count_live_nodes()}</p>
  <h2>Create cluster</h2>
  <form method="post" action="/actions/create-cluster">
    <div class="grid">
      <label>Workers <input name="worker_count" type="number" value="2" min="1" max="16"></label>
      <label>CPUs/worker <input name="cores" type="number" value="1" min="1"></label>
      <label>RAM GB/worker <input name="ram_gb" type="number" value="4" min="1"></label>
      <label>GPUs/worker <input name="gpus" type="number" value="0" min="0" max="8"></label>
      <label>Min joined <input name="min_joined" type="number" value="2" min="1"></label>
      <label>Partial policy
        <select name="partial_policy">
          <option value="accept_partial">accept partial</option>
          <option value="fail_and_cleanup">fail and cleanup</option>
          <option value="continue_waiting">continue waiting</option>
        </select>
      </label>
    </div>
    <button type="submit">Create cluster</button>
  </form>
  <h2>Maintenance</h2>
  <div class="actions">
    <form method="post" action="/actions/preflight"><button type="submit">Run network preflight</button></form>
    <form method="post" action="/actions/reconcile"><button type="submit">Reconcile state</button></form>
    <form method="post" action="/actions/stop-cluster"><button type="submit">Stop cluster</button></form>
    <form method="post" action="/actions/clean-orphans"><button type="submit">Clean orphaned workers</button></form>
  </div>
  <h2>Workers</h2>
  {workers_html or "<p>No workers recorded.</p>"}
  <p><a href="/api/v1/status">JSON status</a> · <a href="/api/v1/auth/status">Auth status</a> · <a href="/healthz">healthz</a></p>
</body></html>"""


def _cluster_payload(state: Any) -> dict[str, Any]:
    op = active_operation()
    payload = {
        "ray_address": ray_address(),
        "manager_ip": manager_pod_ip(),
        "ray_version": _settings.ray_version,
        "cluster_id": _settings.cluster_id,
        "heartbeat_path": str(_heartbeat_path()),
        "ray_running": ray_running(),
        "ray_nodes_alive": count_live_nodes(),
        "worker_image": _settings.worker_image,
        "cluster": asdict(state) if state else None,
        "preflight": state.preflight if state else None,
        "workers": [asdict(w) for w in state.workers] if state else [],
        "joined_workers": len(_store.joined_workers(state)) if state else 0,
        "operation": op.as_dict() if op else None,
    }
    if state and state.phase not in {"Creating", "Idle"}:
        joined = payload["joined_workers"]
        target = state.worker_count or len(state.workers)
        if joined >= target and target > 0:
            payload["success"] = True
        elif joined >= state.min_joined and joined > 0:
            payload["success"] = True
            payload["message"] = f"Partial cluster: {joined}/{target} workers joined"
        elif state.phase in {"Failed", "Stopped"}:
            payload["success"] = False
    return payload
