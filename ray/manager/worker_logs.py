"""Persist CANFAR headless session stdout/stderr under the cluster state dir."""

from __future__ import annotations

from canfar_ops import CanfarOps
from state_store import ClusterState, StateStore, WorkerRecord


def archive_session_logs(
    *,
    canfar: CanfarOps,
    store: StateStore,
    session_id: str,
    worker: WorkerRecord | None = None,
    state: ClusterState | None = None,
) -> str | None:
    """Fetch CANFAR session logs and write them to disk. Returns relative logs_path."""
    try:
        logs = canfar.session_logs(session_id)
    except Exception:  # noqa: BLE001 — local tests / deleted sessions / no CANFAR auth
        logs = ""
    if not logs:
        return worker.logs_path if worker else None

    rel_path = store.save_worker_logs(session_id, logs)
    if worker is not None:
        worker.logs_path = rel_path
        if state is not None:
            store.upsert_worker(state, worker)
        else:
            loaded = store.load()
            if loaded:
                for idx, existing in enumerate(loaded.workers):
                    if existing.session_id == session_id:
                        loaded.workers[idx].logs_path = rel_path
                        store.save(loaded)
                        break
    return rel_path


def read_worker_logs(store: StateStore, session_id: str) -> str | None:
    path = store.worker_log_file(session_id)
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8", errors="replace")
