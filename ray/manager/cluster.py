"""Multi-worker cluster lifecycle (Milestone C)."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any, Literal

from canfar_ops import CanfarOps
from ray_cluster import count_live_nodes, ray_address, wait_for_node_count
from reconcile import reconcile_cluster
from settings import ManagerSettings, manager_pod_ip
from state_store import (
    PARTIAL_POLICIES,
    ClusterState,
    StateStore,
    TERMINAL_WORKER_PHASES,
    WorkerRecord,
)
from workers import build_worker_env, destroy_all_workers, destroy_worker
from worker_logs import archive_session_logs

PartialPolicy = Literal["fail_and_cleanup", "accept_partial", "continue_waiting"]


@dataclass
class ClusterCreateRequest:
    name: str
    worker_count: int = 2
    cores: int = 1
    ram_gb: int = 4
    gpus: int = 0
    min_joined: int | None = None
    partial_policy: PartialPolicy = "accept_partial"
    require_preflight: bool = True


@dataclass
class ClusterCreateResult:
    state: ClusterState
    success: bool
    message: str | None = None


def create_cluster(
    *,
    settings: ManagerSettings,
    canfar: CanfarOps,
    store: StateStore,
    heartbeat_path: str,
    req: ClusterCreateRequest,
) -> ClusterCreateResult:
    auth = canfar.auth_status()
    if not auth.authenticated:
        raise RuntimeError(auth.message or "CANFAR authentication required")

    existing = store.load()
    if existing and existing.phase in {"Creating", "Running", "Degraded", "Stopping"}:
        raise RuntimeError(f"Cluster already active (phase={existing.phase}). Stop it first.")

    if req.partial_policy not in PARTIAL_POLICIES:
        raise RuntimeError(f"Invalid partial_policy: {req.partial_policy}")

    min_joined = req.min_joined if req.min_joined is not None else req.worker_count
    min_joined = max(1, min(min_joined, req.worker_count))

    if req.require_preflight:
        preflight = (existing.preflight if existing else None) or {}
        if not preflight.get("passed"):
            raise RuntimeError("Network preflight has not passed. Run preflight first.")

    state = ClusterState(
        cluster_id=settings.cluster_id,
        name=req.name or settings.cluster_id,
        manager_ip=manager_pod_ip(),
        ray_address=ray_address(),
        phase="Creating",
        worker_count=req.worker_count,
        min_joined=min_joined,
        partial_policy=req.partial_policy,
        preflight=(existing.preflight if existing else None),
        workers=[],
    )
    store.save(state)
    store.log_event(
        "cluster_create_start",
        worker_count=req.worker_count,
        min_joined=min_joined,
        policy=req.partial_policy,
    )

    nodes_before = count_live_nodes()
    tag_safe = time.strftime("%Y%m%d%H%M%S")
    batch_name = f"ray-w-{settings.cluster_id}-{tag_safe}"[:50]

    env = build_worker_env(settings, heartbeat_path)
    env["RAY_WORKER_CPUS"] = str(req.cores)
    env["RAY_WORKER_GPUS"] = str(req.gpus)

    launches = canfar.create_headless(
        name=batch_name,
        image=settings.worker_image,
        cores=req.cores,
        ram=req.ram_gb,
        gpu=req.gpus or None,
        env=env,
        replicas=req.worker_count,
    )

    for launch in launches:
        worker = WorkerRecord(
            session_id=launch.session_id,
            name=launch.name,
            phase="CANFAR Pending",
            cores=req.cores,
            ram_gb=req.ram_gb,
            gpus=req.gpus,
        )
        store.upsert_worker(state, worker)

    deadline = time.monotonic() + settings.worker_launch_timeout_seconds
    poll = 10
    while time.monotonic() < deadline:
        state = reconcile_cluster(canfar=canfar, store=store, state=state) or state
        joined = len(store.joined_workers(state))
        if joined >= req.worker_count:
            state.phase = "Running"
            store.save(state)
            store.log_event("cluster_create_done", phase=state.phase, joined=joined)
            return ClusterCreateResult(state=state, success=True)

        if req.partial_policy == "accept_partial" and joined >= min_joined:
            pending = _pending_workers(state)
            if not pending or all(w.canfar_status in {"Failed", "Error"} for w in pending):
                state.phase = "Degraded"
                store.save(state)
                store.log_event("cluster_create_done", phase=state.phase, joined=joined)
                return ClusterCreateResult(
                    state=state,
                    success=True,
                    message=f"Partial cluster: {joined}/{req.worker_count} workers joined",
                )

        failed = [w for w in state.workers if w.phase == "CANFAR Failed"]
        if failed and req.partial_policy == "fail_and_cleanup":
            stop_cluster(canfar=canfar, store=store, force=True)
            state = store.load() or state
            state.phase = "Failed"
            store.save(state)
            return ClusterCreateResult(
                state=state,
                success=False,
                message="Worker startup failed; cluster cleaned up",
            )

        if req.partial_policy != "continue_waiting" and joined >= min_joined:
            still_starting = any(
                w.phase in {"CANFAR Pending", "CANFAR Running", "Ray Joining"}
                for w in state.workers
            )
            if not still_starting and joined < req.worker_count:
                if req.partial_policy == "fail_and_cleanup":
                    stop_cluster(canfar=canfar, store=store, force=True)
                    state = store.load() or state
                    state.phase = "Failed"
                    store.save(state)
                    return ClusterCreateResult(
                        state=state,
                        success=False,
                        message=f"Only {joined}/{req.worker_count} joined; cleaned up",
                    )
                state.phase = "Degraded"
                store.save(state)
                return ClusterCreateResult(
                    state=state,
                    success=joined >= min_joined,
                    message=f"Partial cluster: {joined}/{req.worker_count} workers joined",
                )

        time.sleep(poll)

    final_nodes = wait_for_node_count(
        minimum=nodes_before + min_joined,
        timeout_seconds=30,
        poll_seconds=5,
    )
    state = reconcile_cluster(canfar=canfar, store=store, state=state) or state
    joined = len(store.joined_workers(state))

    if joined >= req.worker_count:
        state.phase = "Running"
        success = True
        message = None
    elif joined >= min_joined:
        state.phase = "Degraded"
        success = True
        message = f"Timeout with partial join: {joined}/{req.worker_count}"
    elif req.partial_policy == "fail_and_cleanup":
        stop_cluster(canfar=canfar, store=store, force=True)
        state = store.load() or state
        state.phase = "Failed"
        success = False
        message = "Startup timeout; cluster cleaned up"
    else:
        state.phase = "Failed"
        success = False
        message = f"Startup timeout: {joined}/{req.worker_count} joined, nodes={final_nodes}"

    store.save(state)
    store.log_event("cluster_create_done", phase=state.phase, joined=joined, success=success)
    _archive_worker_logs(canfar=canfar, store=store, state=state)
    return ClusterCreateResult(state=state, success=success, message=message)


def stop_cluster(
    *,
    canfar: CanfarOps,
    store: StateStore,
    force: bool = False,
    wait_timeout: int = 600,
) -> ClusterState | None:
    state = store.load()
    if not state:
        return None

    state.phase = "Stopping"
    store.save(state)
    store.log_event("cluster_stop_start", force=force)

    state = store.load() or state
    _archive_worker_logs(canfar=canfar, store=store, state=state)

    destroy_all_workers(canfar=canfar, store=store)
    state = store.load() or state

    deadline = time.monotonic() + wait_timeout
    while time.monotonic() < deadline:
        state = reconcile_cluster(canfar=canfar, store=store, state=state) or state
        active = [w for w in state.workers if w.phase not in TERMINAL_WORKER_PHASES]
        if not active:
            break
        time.sleep(10)

    for worker in state.workers:
        if worker.phase not in TERMINAL_WORKER_PHASES:
            worker.phase = "Stopped"
    state.phase = "Stopped"
    store.save(state)
    store.log_event("cluster_stop_done", phase=state.phase)
    return state


def retry_worker(
    *,
    settings: ManagerSettings,
    canfar: CanfarOps,
    store: StateStore,
    heartbeat_path: str,
    session_id: str,
) -> WorkerRecord:
    state = store.load()
    if not state:
        raise RuntimeError("No cluster state")

    worker = next((w for w in state.workers if w.session_id == session_id), None)
    if not worker:
        raise RuntimeError(f"Unknown worker session {session_id}")

    if worker.phase not in {"CANFAR Failed", "Ray Unhealthy", "Orphaned"}:
        raise RuntimeError(f"Worker not in retriable state (phase={worker.phase})")

    destroy_worker(canfar=canfar, store=store, session_id=session_id)
    worker.phase = "Stopped"
    store.upsert_worker(state, worker)

    tag_safe = time.strftime("%Y%m%d%H%M%S")
    name = f"ray-retry-{settings.cluster_id}-{tag_safe}"[:60]
    env = build_worker_env(settings, heartbeat_path)
    env["RAY_WORKER_CPUS"] = str(worker.cores or 1)
    env["RAY_WORKER_GPUS"] = str(worker.gpus or 0)

    nodes_before = count_live_nodes()
    launch = canfar.create_headless(
        name=name,
        image=settings.worker_image,
        cores=worker.cores,
        ram=worker.ram_gb,
        gpu=worker.gpus or None,
        env=env,
        replicas=1,
    )[0]

    replacement = WorkerRecord(
        session_id=launch.session_id,
        name=launch.name,
        phase="CANFAR Pending",
        cores=worker.cores,
        ram_gb=worker.ram_gb,
        gpus=worker.gpus,
    )
    store.upsert_worker(state, replacement)

    status = canfar.wait_for_status(
        launch.session_id,
        target={"Running"},
        timeout_seconds=settings.worker_launch_timeout_seconds,
    )
    replacement.canfar_status = status
    if status != "Running":
        replacement.phase = "CANFAR Failed"
        replacement.last_error = f"retry status={status}"
        archive_session_logs(
            canfar=canfar,
            store=store,
            session_id=launch.session_id,
            worker=replacement,
            state=state,
        )
        store.upsert_worker(state, replacement)
        return replacement

    replacement.phase = "Ray Joining"
    store.upsert_worker(state, replacement)
    wait_for_node_count(
        minimum=nodes_before + 1,
        timeout_seconds=min(300, settings.worker_launch_timeout_seconds),
    )
    state = reconcile_cluster(canfar=canfar, store=store, state=state) or state
    updated = next(w for w in state.workers if w.session_id == launch.session_id)
    store.log_event("worker_retry_done", session_id=launch.session_id, joined=updated.ray_joined)
    return updated


def clean_orphaned_workers(
    *,
    settings: ManagerSettings,
    canfar: CanfarOps,
    store: StateStore,
) -> list[dict[str, Any]]:
    prefix = f"ray-w-{settings.cluster_id}"
    retry_prefix = f"ray-retry-{settings.cluster_id}"
    state = store.load()
    known = {w.session_id for w in state.workers} if state else set()

    destroyed: list[dict[str, Any]] = []
    for row in canfar.list_headless_sessions(name_prefix=prefix):
        sid = str(row.get("id") or "")
        if sid and sid not in known:
            ok = canfar.destroy(sid)
            destroyed.append({"session_id": sid, "name": row.get("name"), "destroyed": ok})
    for row in canfar.list_headless_sessions(name_prefix=retry_prefix):
        sid = str(row.get("id") or "")
        if sid and sid not in known:
            ok = canfar.destroy(sid)
            destroyed.append({"session_id": sid, "name": row.get("name"), "destroyed": ok})

    store.log_event("orphan_cleanup", count=len(destroyed))
    return destroyed


def _pending_workers(state: ClusterState) -> list[WorkerRecord]:
    return [
        w
        for w in state.workers
        if w.phase in {"Requested", "CANFAR Pending", "CANFAR Running", "Ray Joining"}
    ]


def _archive_worker_logs(*, canfar: CanfarOps, store: StateStore, state: ClusterState | None) -> None:
    if not state:
        return
    for worker in state.workers:
        archive_session_logs(
            canfar=canfar,
            store=store,
            session_id=worker.session_id,
            worker=worker,
            state=state,
        )
