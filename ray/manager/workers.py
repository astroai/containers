"""Launch and destroy CANFAR Ray worker sessions."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

from canfar_ops import CanfarOps
from ray_cluster import count_live_nodes, ray_address, wait_for_nodes
from settings import ManagerSettings, manager_pod_ip
from state_store import StateStore, WorkerRecord, ClusterState
from worker_logs import archive_session_logs


@dataclass
class WorkerLaunchResult:
    worker: WorkerRecord
    logs_excerpt: str | None = None


def build_worker_env(settings: ManagerSettings, heartbeat_path: str) -> dict[str, str]:
    spill = f"{settings.scratch_dir.rstrip('/')}/ray/{settings.cluster_id}"
    env = {
        "RAY_CLUSTER_ID": settings.cluster_id,
        "RAY_HEAD_IP": manager_pod_ip(),
        "RAY_HEAD_PORT": str(settings.ray_head_port),
        "RAY_VERSION_EXPECTED": settings.ray_version,
        "RAY_WORKER_CPUS": "1",
        "RAY_WORKER_GPUS": "0",
        "RAY_SPILL_DIR": spill,
        "RAY_MANAGER_HEARTBEAT_PATH": heartbeat_path,
        "RAY_MANAGER_HEARTBEAT_TIMEOUT_SECONDS": str(settings.heartbeat_timeout_seconds),
    }
    for key in (
        "RAY_NODE_MANAGER_PORT",
        "RAY_OBJECT_MANAGER_PORT",
        "RAY_RUNTIME_ENV_AGENT_PORT",
        "RAY_DASHBOARD_AGENT_GRPC_PORT",
        "RAY_MIN_WORKER_PORT",
        "RAY_MAX_WORKER_PORT",
    ):
        val = __import__("os").environ.get(key)
        if val:
            env[key] = val
    return env


def launch_worker(
    *,
    settings: ManagerSettings,
    canfar: CanfarOps,
    store: StateStore,
    heartbeat_path: str,
    cores: int = 1,
    ram_gb: int = 4,
    gpus: int = 0,
    require_preflight: bool = True,
) -> WorkerLaunchResult:
    auth = canfar.auth_status()
    if not auth.authenticated:
        raise RuntimeError(auth.message or "CANFAR authentication required")

    state = store.load()
    if require_preflight:
        preflight = (state.preflight if state else None) or {}
        if not preflight.get("passed"):
            raise RuntimeError("Network preflight has not passed. Run preflight first.")

    nodes_before = count_live_nodes()
    tag_safe = time.strftime("%Y%m%d%H%M%S")
    worker_name = f"ray-w-{settings.cluster_id}-{tag_safe}"[:60]

    env = build_worker_env(settings, heartbeat_path)
    env["RAY_WORKER_CPUS"] = str(cores)
    env["RAY_WORKER_GPUS"] = str(gpus)

    store.log_event("worker_launch_start", name=worker_name, image=settings.worker_image)
    launch = canfar.create_headless(
        name=worker_name,
        image=settings.worker_image,
        cores=cores,
        ram=ram_gb,
        gpu=gpus or None,
        env=env,
        replicas=1,
    )[0]

    worker = WorkerRecord(
        session_id=launch.session_id,
        name=launch.name,
        phase="CANFAR Pending",
        cores=cores,
        ram_gb=ram_gb,
        gpus=gpus,
    )
    if state is None:
        state = ClusterState(
            cluster_id=settings.cluster_id,
            manager_ip=manager_pod_ip(),
            ray_address=ray_address(),
            phase="Creating",
            worker_count=1,
            min_joined=1,
        )
    store.upsert_worker(state, worker)

    status = canfar.wait_for_status(
        launch.session_id,
        target={"Running"},
        timeout_seconds=settings.worker_launch_timeout_seconds,
    )
    worker.canfar_status = status
    worker.phase = "CANFAR Running" if status == "Running" else f"CANFAR {status}"
    store.upsert_worker(state, worker)

    if status != "Running":
        worker.phase = "CANFAR Failed"
        worker.last_error = f"worker session status={status}"
        archive_session_logs(
            canfar=canfar,
            store=store,
            session_id=launch.session_id,
            worker=worker,
            state=state,
        )
        store.upsert_worker(state, worker)
        store.log_event("worker_launch_failed", session_id=launch.session_id, status=status)
        logs = canfar.session_logs(launch.session_id)
        return WorkerLaunchResult(worker=worker, logs_excerpt=_tail(logs))

    worker.phase = "Ray Joining"
    store.upsert_worker(state, worker)

    target_nodes = nodes_before + 1
    nodes = wait_for_nodes(
        minimum=target_nodes,
        timeout_seconds=min(300, settings.worker_launch_timeout_seconds),
    )
    final_count = count_live_nodes(nodes=nodes)
    worker.ray_joined = final_count >= target_nodes
    worker.phase = "Ray Healthy" if worker.ray_joined else "Ray Unhealthy"
    if not worker.ray_joined:
        worker.last_error = f"Ray nodes {final_count}, expected >={target_nodes}"
        archive_session_logs(
            canfar=canfar,
            store=store,
            session_id=launch.session_id,
            worker=worker,
            state=state,
        )
    if worker.ray_joined:
        state.phase = "Running"
    store.upsert_worker(state, worker)
    store.log_event(
        "worker_launch_done",
        session_id=launch.session_id,
        ray_joined=worker.ray_joined,
        nodes=final_count,
    )
    return WorkerLaunchResult(worker=worker)


def destroy_worker(
    *,
    canfar: CanfarOps,
    store: StateStore,
    session_id: str,
) -> dict[str, Any]:
    state = store.load()
    worker = None
    if state:
        worker = next((w for w in state.workers if w.session_id == session_id), None)
    archive_session_logs(
        canfar=canfar,
        store=store,
        session_id=session_id,
        worker=worker,
        state=state,
    )
    ok = canfar.destroy(session_id)
    state = store.load()
    if state:
        for worker in state.workers:
            if worker.session_id == session_id:
                worker.phase = "Stopping" if ok else worker.phase
                worker.canfar_status = "Terminating"
                store.upsert_worker(state, worker)
    store.log_event("worker_destroy", session_id=session_id, destroyed=ok)
    return {"session_id": session_id, "destroyed": ok}


def destroy_all_workers(*, canfar: CanfarOps, store: StateStore) -> list[dict[str, Any]]:
    state = store.load()
    if not state:
        return []
    results = []
    for worker in list(state.workers):
        if worker.phase in {"Stopped", "Stopping"}:
            continue
        results.append(destroy_worker(canfar=canfar, store=store, session_id=worker.session_id))
        worker.phase = "Stopped"
        store.upsert_worker(state, worker)
    return results


def _tail(text: str, lines: int = 40) -> str:
    rows = text.splitlines()
    return "\n".join(rows[-lines:])
