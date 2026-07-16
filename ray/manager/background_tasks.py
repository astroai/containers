"""Run long CANFAR/Ray operations in background threads (avoid ingress timeouts)."""

from __future__ import annotations

import threading
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime


@dataclass
class OperationStatus:
    kind: str
    running: bool
    started_at: str
    error: str | None = None

    def as_dict(self) -> dict[str, str | bool | None]:
        return {
            "kind": self.kind,
            "running": self.running,
            "started_at": self.started_at,
            "error": self.error,
        }


_lock = threading.Lock()
_active: OperationStatus | None = None


def _utc_now() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat()


def active_operation() -> OperationStatus | None:
    with _lock:
        return _active


def start_background(kind: str, fn: Callable[[], None]) -> bool:
    global _active
    with _lock:
        if _active and _active.running:
            return False
        _active = OperationStatus(kind=kind, running=True, started_at=_utc_now())

    def wrapper() -> None:
        global _active
        error: str | None = None
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 — surface in status payload
            error = str(exc)
        finally:
            with _lock:
                if _active and _active.kind == kind:
                    _active = OperationStatus(
                        kind=kind,
                        running=False,
                        started_at=_active.started_at,
                        error=error,
                    )

    threading.Thread(target=wrapper, daemon=True, name=f"ray-{kind}").start()
    return True
