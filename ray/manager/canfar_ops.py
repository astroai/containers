"""CANFAR session API helpers for the Ray manager."""

from __future__ import annotations

import os
import re
import time
from dataclasses import dataclass
from typing import Any

from canfar.models.config import Configuration
from canfar.sessions import Session


@dataclass
class AuthStatus:
    authenticated: bool
    idp: str | None = None
    server: str | None = None
    message: str | None = None


@dataclass
class SessionLaunch:
    session_id: str
    name: str


class CanfarOps:
    def __init__(self) -> None:
        self._session = Session()

    def auth_status(self) -> AuthStatus:
        config = Configuration()
        idp = config.active.authentication
        server = config.active.server
        if not idp:
            return AuthStatus(
                authenticated=False,
                message="No CANFAR authentication configured. Run: canfar auth login",
            )
        try:
            config.get_credential(idp)
        except KeyError:
            return AuthStatus(
                authenticated=False,
                idp=idp,
                message=f"No saved credentials for IDP '{idp}'. Run: canfar auth login",
            )
        try:
            self._session.fetch(view="all")
        except Exception as exc:  # noqa: BLE001 — surface to UI
            return AuthStatus(
                authenticated=False,
                idp=idp,
                server=server,
                message=str(exc),
            )
        return AuthStatus(authenticated=True, idp=idp, server=server)

    def create_headless(
        self,
        *,
        name: str,
        image: str,
        cores: int | None = None,
        ram: int | None = None,
        gpu: int | None = None,
        cmd: str | None = None,
        args: str | None = None,
        env: dict[str, Any] | None = None,
        replicas: int = 1,
    ) -> list[SessionLaunch]:
        registry_env = _registry_env()
        merged_env = dict(registry_env)
        if env:
            merged_env.update(env)
        ids = self._session.create(
            name=name,
            image=image,
            cores=cores,
            ram=ram,
            gpu=gpu,
            kind="headless",
            cmd=cmd,
            args=args,
            env=merged_env or None,
            replicas=replicas,
        )
        if not ids:
            raise RuntimeError("CANFAR session create returned no session ID")
        launches: list[SessionLaunch] = []
        for idx, session_id in enumerate(ids):
            worker_name = name if replicas == 1 else f"{name}-{idx + 1}"
            launches.append(SessionLaunch(session_id=session_id.strip(), name=worker_name))
        return launches

    def list_headless_sessions(self, *, name_prefix: str) -> list[dict[str, Any]]:
        rows = self._session.fetch(kind="headless", view="all")
        return [row for row in rows if str(row.get("name", "")).startswith(name_prefix)]

    def session_info(self, session_id: str) -> dict[str, Any]:
        rows = self._session.info(session_id)
        if not rows:
            return {}
        return rows[0]

    def session_status(self, session_id: str) -> str:
        info = self.session_info(session_id)
        return str(info.get("status") or "Unknown")

    def session_logs(self, session_id: str) -> str:
        logs = self._session.logs(session_id)
        if not logs:
            return ""
        return logs.get(session_id, "")

    def wait_for_status(
        self,
        session_id: str,
        *,
        target: set[str],
        timeout_seconds: int,
        poll_seconds: int = 10,
    ) -> str:
        deadline = time.monotonic() + timeout_seconds
        status = "Unknown"
        while time.monotonic() < deadline:
            status = self.session_status(session_id)
            if status in target:
                return status
            if status in {"Failed", "Error", "Terminating"}:
                return status
            time.sleep(poll_seconds)
        return status

    def destroy(self, session_id: str) -> bool:
        try:
            result = self._session.destroy(session_id)
            return bool(result.get(session_id))
        except Exception:  # noqa: BLE001 — missing auth or unknown session
            return False


def _registry_env() -> dict[str, str]:
    """Harbor pull credentials for headless worker launches (maintainer/testing)."""
    out: dict[str, str] = {}
    mapping = {
        "CANFAR_REGISTRY__USERNAME": os.environ.get("CANFAR_REGISTRY__USERNAME"),
        "CANFAR_REGISTRY__SECRET": os.environ.get("CANFAR_REGISTRY__SECRET"),
        "CANFAR_REGISTRY__URL": os.environ.get("CANFAR_REGISTRY__URL"),
    }
    for key, val in mapping.items():
        if val:
            out[key] = val
    return out


def parse_probe_logs(logs: str) -> dict[str, Any]:
    worker_ip = None
    checks: list[dict[str, str]] = []
    overall = "UNKNOWN"
    for line in logs.splitlines():
        if line.startswith("WORKER_IP="):
            worker_ip = line.split("=", 1)[1].strip()
            continue
        match = re.match(r"PROBE worker->manager:(\d+) (PASS|FAIL)", line)
        if match:
            checks.append({"port": match.group(1), "result": match.group(2)})
            continue
        if line.startswith("PROBE_RESULT "):
            overall = line.split(" ", 1)[1].strip()
    return {"worker_ip": worker_ip, "checks": checks, "result": overall}


def manager_to_worker_probe(manager_ip: str, worker_ip: str, ports: list[int]) -> list[dict[str, str]]:
    import socket

    results: list[dict[str, str]] = []
    for port in ports:
        label = f"manager->worker:{port}"
        try:
            with socket.create_connection((worker_ip, port), timeout=10):
                results.append({"check": label, "result": "PASS"})
        except OSError:
            results.append({"check": label, "result": "FAIL"})
    return results
