"""CANFAR Ray Manager web app — cluster lifecycle (Milestone C)."""

from __future__ import annotations

import os
import subprocess
from dataclasses import asdict
from pathlib import Path
from typing import Any, Literal

from fastapi import FastAPI, Form, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from pydantic import BaseModel, Field

from canfar_ops import CanfarOps
from cluster import (
    ClusterCreateRequest,
    clean_orphaned_workers,
    create_cluster,
    retry_worker,
    stop_cluster,
)
from preflight import run_preflight
from ray_cluster import count_live_nodes, list_ray_nodes, ray_address, ray_running
from reconcile import reconcile_cluster
from settings import ManagerSettings, manager_pod_ip
from state_store import StateStore
from workers import destroy_all_workers, destroy_worker, launch_worker

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


@app.post("/api/v1/preflight/run")
def api_preflight_run() -> JSONResponse:
    _touch_heartbeat()
    report = run_preflight(_settings, _canfar, _store)
    code = 200 if report.passed else 503
    return JSONResponse(report.as_dict(), status_code=code)


@app.post("/api/v1/cluster/create")
def api_cluster_create(body: ClusterCreateBody) -> JSONResponse:
    _touch_heartbeat()
    try:
        result = create_cluster(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
            req=ClusterCreateRequest(
                name=body.name or _settings.cluster_id,
                worker_count=body.worker_count,
                cores=body.cores,
                ram_gb=body.ram_gb,
                gpus=body.gpus,
                min_joined=body.min_joined,
                partial_policy=body.partial_policy,
                require_preflight=body.require_preflight,
            ),
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


@app.delete("/api/v1/workers/{session_id}")
def api_workers_destroy(session_id: str) -> JSONResponse:
    return JSONResponse(destroy_worker(canfar=_canfar, store=_store, session_id=session_id))


@app.post("/api/v1/workers/destroy-all")
def api_workers_destroy_all() -> JSONResponse:
    results = destroy_all_workers(canfar=_canfar, store=_store)
    return JSONResponse({"destroyed": results})


@app.get("/api/v1/ray/nodes")
def api_ray_nodes() -> JSONResponse:
    return JSONResponse({"nodes": list_ray_nodes(), "alive": count_live_nodes()})


@app.post("/actions/preflight")
def action_preflight() -> RedirectResponse:
    run_preflight(_settings, _canfar, _store)
    return RedirectResponse("/", status_code=303)


@app.post("/actions/create-cluster")
def action_create_cluster(
    worker_count: int = Form(2),
    cores: int = Form(1),
    ram_gb: int = Form(4),
    min_joined: int = Form(2),
    partial_policy: str = Form("accept_partial"),
) -> RedirectResponse:
    try:
        create_cluster(
            settings=_settings,
            canfar=_canfar,
            store=_store,
            heartbeat_path=str(_heartbeat_path()),
            req=ClusterCreateRequest(
                name=_settings.cluster_id,
                worker_count=worker_count,
                cores=cores,
                ram_gb=ram_gb,
                min_joined=min_joined,
                partial_policy=partial_policy,  # type: ignore[arg-type]
                require_preflight=True,
            ),
        )
    except RuntimeError:
        pass
    return RedirectResponse("/", status_code=303)


@app.post("/actions/stop-cluster")
def action_stop_cluster() -> RedirectResponse:
    stop_cluster(canfar=_canfar, store=_store)
    return RedirectResponse("/", status_code=303)


@app.post("/actions/reconcile")
def action_reconcile() -> RedirectResponse:
    reconcile_cluster(canfar=_canfar, store=_store)
    return RedirectResponse("/", status_code=303)


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    _touch_heartbeat()
    auth = _canfar.auth_status()
    state = reconcile_cluster(canfar=_canfar, store=_store)
    preflight = (state.preflight if state else None) or {}

    workers_html = ""
    if state and state.workers:
        rows = []
        for w in state.workers:
            retry = ""
            if w.phase in {"CANFAR Failed", "Ray Unhealthy", "Orphaned"}:
                retry = (
                    f'<form style="display:inline" method="post" '
                    f'action="/api/v1/workers/{w.session_id}/retry">'
                    f'<button type="submit">Retry</button></form>'
                )
            rows.append(
                f"<tr><td>{w.name}</td><td><code>{w.session_id}</code></td>"
                f"<td>{w.phase}</td><td>{w.canfar_status or '—'}</td>"
                f"<td>{w.worker_ip or '—'}</td>"
                f"<td>{'yes' if w.ray_joined else 'no'}</td>"
                f"<td>{w.last_error or ''} {retry}</td></tr>"
            )
        workers_html = (
            "<table border='1' cellpadding='4'>"
            "<tr><th>Name</th><th>Session</th><th>Phase</th><th>CANFAR</th>"
            "<th>IP</th><th>Ray</th><th>Notes</th></tr>"
            + "".join(rows)
            + "</table>"
        )

    auth_line = (
        f"<span style='color:green'>Authenticated ({auth.idp})</span>"
        if auth.authenticated
        else (
            "<span style='color:red'>Not authenticated</span> — "
            "run <code>canfar auth login</code> in a terminal session, then refresh."
        )
    )
    pf_line = (
        f"<span style='color:green'>Passed</span> (worker IP {preflight.get('worker_ip', '?')})"
        if preflight.get("passed")
        else "<span style='color:orange'>Not run or failed</span>"
    )
    cluster_phase = state.phase if state else "Idle"
    joined = len(_store.joined_workers(state)) if state else 0
    target = state.worker_count if state else 0

    return f"""<!DOCTYPE html>
<html><head><title>CANFAR Ray Manager</title></head>
<body>
  <h1>CANFAR Ray Manager</h1>
  <p>Ray: <code>{ray_address()}</code> · cluster <code>{_settings.cluster_id}</code></p>
  <p>Cluster phase: <strong>{cluster_phase}</strong> · workers joined: {joined}/{target or '—'}</p>
  <p>CANFAR auth: {auth_line}</p>
  <p>Network preflight: {pf_line}</p>
  <p>Live Ray nodes: {count_live_nodes()}</p>
  <h2>Create cluster</h2>
  <form method="post" action="/actions/create-cluster">
    <label>Workers <input name="worker_count" type="number" value="2" min="1" max="16"></label>
    <label>CPUs/worker <input name="cores" type="number" value="1" min="1"></label>
    <label>RAM GB/worker <input name="ram_gb" type="number" value="4" min="1"></label>
    <label>Min joined <input name="min_joined" type="number" value="2" min="1"></label>
    <label>Partial policy
      <select name="partial_policy">
        <option value="accept_partial">accept partial</option>
        <option value="fail_and_cleanup">fail and cleanup</option>
        <option value="continue_waiting">continue waiting</option>
      </select>
    </label>
    <button type="submit">Create cluster</button>
  </form>
  <h2>Maintenance</h2>
  <form method="post" action="/actions/preflight"><button type="submit">Run network preflight</button></form>
  <form method="post" action="/actions/reconcile"><button type="submit">Reconcile state</button></form>
  <form method="post" action="/actions/stop-cluster"><button type="submit">Stop cluster</button></form>
  <form method="post" action="/api/v1/cluster/clean-orphans"><button type="submit">Clean orphaned workers</button></form>
  <h2>Workers</h2>
  {workers_html or "<p>No workers recorded.</p>"}
  <p><a href="/api/v1/status">JSON status</a> · <a href="/healthz">healthz</a></p>
</body></html>"""


def _cluster_payload(state: Any) -> dict[str, Any]:
    return {
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
    }
