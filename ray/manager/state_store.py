"""Persist cluster/worker state under ~/.canfar-ray/clusters/<id>/."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

PARTIAL_POLICIES = frozenset({"fail_and_cleanup", "accept_partial", "continue_waiting"})

TERMINAL_CLUSTER_PHASES = frozenset({"Stopped", "Failed", "Idle"})
ACTIVE_CLUSTER_PHASES = frozenset({"Creating", "Running", "Degraded", "Stopping"})

TERMINAL_WORKER_PHASES = frozenset({"Stopped", "Stopping", "Orphaned"})


def _utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def cluster_state_dir(cluster_id: str | None = None) -> Path:
    home = Path(os.environ.get("HOME", "/tmp"))
    cid = cluster_id or os.environ.get("RAY_CLUSTER_ID", "default")
    return home / ".canfar-ray" / "clusters" / cid


@dataclass
class WorkerRecord:
    session_id: str
    name: str
    phase: str = "Requested"
    canfar_status: str | None = None
    ray_joined: bool = False
    ray_node_id: str | None = None
    worker_ip: str | None = None
    cores: int | None = None
    ram_gb: int | None = None
    gpus: int = 0
    created_at: str = field(default_factory=_utc_now)
    updated_at: str = field(default_factory=_utc_now)
    last_error: str | None = None


@dataclass
class ClusterState:
    cluster_id: str
    manager_ip: str
    ray_address: str
    name: str = ""
    phase: str = "Idle"
    worker_count: int = 0
    min_joined: int = 1
    partial_policy: str = "accept_partial"
    preflight: dict[str, Any] | None = None
    workers: list[WorkerRecord] = field(default_factory=list)
    updated_at: str = field(default_factory=_utc_now)


class StateStore:
    def __init__(self, cluster_id: str | None = None) -> None:
        self.dir = cluster_state_dir(cluster_id)
        self.state_path = self.dir / "state.json"
        self.events_path = self.dir / "events.jsonl"

    def ensure_dir(self) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(self.dir, 0o700)
        except OSError:
            pass

    def log_event(self, event: str, **payload: Any) -> None:
        self.ensure_dir()
        row = {"ts": _utc_now(), "event": event, **payload}
        with self.events_path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(row, sort_keys=True) + "\n")

    def load(self) -> ClusterState | None:
        if not self.state_path.is_file():
            return None
        raw = json.loads(self.state_path.read_text(encoding="utf-8"))
        workers = [WorkerRecord(**w) for w in raw.get("workers", [])]
        return ClusterState(
            cluster_id=raw["cluster_id"],
            manager_ip=raw["manager_ip"],
            ray_address=raw["ray_address"],
            name=raw.get("name", ""),
            phase=raw.get("phase", "Idle"),
            worker_count=int(raw.get("worker_count", 0)),
            min_joined=int(raw.get("min_joined", 1)),
            partial_policy=raw.get("partial_policy", "accept_partial"),
            preflight=raw.get("preflight"),
            workers=workers,
            updated_at=raw.get("updated_at", _utc_now()),
        )

    def save(self, state: ClusterState) -> None:
        self.ensure_dir()
        state.updated_at = _utc_now()
        payload = asdict(state)
        fd, tmp = tempfile.mkstemp(prefix="state-", dir=self.dir)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                json.dump(payload, fh, indent=2, sort_keys=True)
                fh.write("\n")
            os.replace(tmp, self.state_path)
            try:
                os.chmod(self.state_path, 0o600)
            except OSError:
                pass
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    def upsert_worker(self, state: ClusterState, worker: WorkerRecord) -> None:
        worker.updated_at = _utc_now()
        for idx, existing in enumerate(state.workers):
            if existing.session_id == worker.session_id:
                state.workers[idx] = worker
                break
        else:
            state.workers.append(worker)
        self.save(state)

    def active_workers(self, state: ClusterState) -> list[WorkerRecord]:
        return [w for w in state.workers if w.phase not in TERMINAL_WORKER_PHASES]

    def joined_workers(self, state: ClusterState) -> list[WorkerRecord]:
        return [w for w in state.workers if w.ray_joined and w.phase not in TERMINAL_WORKER_PHASES]
