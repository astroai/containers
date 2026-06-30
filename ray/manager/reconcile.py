"""Reconcile persisted cluster state with CANFAR and Ray."""

from __future__ import annotations

from canfar_ops import CanfarOps
from ray_cluster import list_ray_nodes, live_worker_node_ips, node_ip_to_id, parse_worker_ip_from_logs, ray_address
from settings import manager_pod_ip
from state_store import (
    ACTIVE_CLUSTER_PHASES,
    ClusterState,
    StateStore,
    TERMINAL_WORKER_PHASES,
    WorkerRecord,
)
from worker_logs import archive_session_logs, read_worker_logs


def reconcile_cluster(
    *,
    canfar: CanfarOps,
    store: StateStore,
    state: ClusterState | None = None,
) -> ClusterState | None:
    state = state or store.load()
    if not state:
        return None

    state.manager_ip = manager_pod_ip()
    state.ray_address = ray_address()
    if state.preflight:
        pf_ip = str(state.preflight.get("manager_ip") or "")
        if pf_ip and pf_ip != state.manager_ip:
            state.preflight = None

    nodes = list_ray_nodes()
    ray_ips = live_worker_node_ips(nodes=nodes)
    head_ip = manager_pod_ip()
    worker_ray_ips = {ip for ip in ray_ips if ip != head_ip}
    ip_to_node = node_ip_to_id(nodes=nodes)
    auth = canfar.auth_status()

    for worker in state.workers:
        if worker.phase in TERMINAL_WORKER_PHASES:
            continue
        if auth.authenticated:
            info = canfar.session_info(worker.session_id)
            if info:
                worker.canfar_status = str(info.get("status") or "Unknown")
                _apply_canfar_phase(worker)
                enrich_worker_failure(canfar, worker)
            elif worker.canfar_status not in {None, "Unknown"}:
                worker.phase = "Orphaned"
                worker.last_error = "session not found in CANFAR"
            archive_session_logs(
                canfar=canfar,
                store=store,
                session_id=worker.session_id,
                worker=worker,
                state=state,
            )
            if not worker.worker_ip:
                saved = read_worker_logs(store, worker.session_id)
                if saved:
                    worker.worker_ip = parse_worker_ip_from_logs(saved)
        if worker.worker_ip and worker.worker_ip in worker_ray_ips:
            worker.ray_joined = True
            worker.ray_node_id = ip_to_node.get(worker.worker_ip)
            if worker.phase not in TERMINAL_WORKER_PHASES and worker.canfar_status == "Running":
                worker.phase = "Ray Healthy"
        elif worker.canfar_status == "Running" and not worker.ray_joined:
            worker.phase = "Ray Joining"

    if state.phase in ACTIVE_CLUSTER_PHASES:
        _refresh_cluster_phase(state)

    store.save(state)
    store.log_event(
        "reconcile",
        phase=state.phase,
        joined=len(store.joined_workers(state)),
        workers=len(state.workers),
    )
    return state


def _apply_canfar_phase(worker: WorkerRecord) -> None:
    status = worker.canfar_status or "Unknown"
    if status in {"Pending"}:
        worker.phase = "CANFAR Pending"
    elif status == "Running":
        if not worker.ray_joined:
            worker.phase = "Ray Joining" if worker.phase != "Ray Healthy" else worker.phase
    elif status in {"Failed", "Error"}:
        worker.phase = "CANFAR Failed"
        worker.last_error = f"CANFAR status={status}"
    elif status in {"Succeeded", "Completed", "Terminating"}:
        worker.phase = "Stopped"


def enrich_worker_failure(canfar: CanfarOps, worker: WorkerRecord) -> None:
    if worker.phase != "CANFAR Failed":
        return
    detail = canfar.session_failure_detail(worker.session_id)
    if detail:
        worker.last_error = f"{worker.last_error}; {detail}"


def _refresh_cluster_phase(state: ClusterState) -> None:
    joined = sum(1 for w in state.workers if w.ray_joined and w.phase not in TERMINAL_WORKER_PHASES)
    active = sum(1 for w in state.workers if w.phase not in TERMINAL_WORKER_PHASES)
    target = state.worker_count or len(state.workers)

    if state.phase == "Stopping":
        if active == 0:
            state.phase = "Stopped"
        return

    if joined >= target and target > 0:
        state.phase = "Running"
    elif joined >= state.min_joined and joined > 0:
        state.phase = "Degraded"
    elif active == 0 and state.phase == "Creating":
        state.phase = "Failed"
    elif state.phase == "Creating" and joined == 0 and all(
        w.phase in {"CANFAR Failed", "Stopped", "Orphaned"} for w in state.workers
    ):
        state.phase = "Failed"
