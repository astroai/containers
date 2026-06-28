"""CANFAR network preflight — one headless probe session."""

from __future__ import annotations

import os
import socket
import time
from dataclasses import dataclass
from typing import Any

from canfar_ops import CanfarOps, manager_to_worker_probe, parse_probe_logs
from settings import ManagerSettings, manager_pod_ip, ray_probe_ports
from state_store import ClusterState, StateStore


@dataclass
class PreflightReport:
    passed: bool
    manager_ip: str
    worker_ip: str | None
    worker_to_manager: list[dict[str, str]]
    manager_to_worker: list[dict[str, str]]
    probe_session_id: str | None
    message: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "passed": self.passed,
            "manager_ip": self.manager_ip,
            "worker_ip": self.worker_ip,
            "worker_to_manager": self.worker_to_manager,
            "manager_to_worker": self.manager_to_worker,
            "probe_session_id": self.probe_session_id,
            "message": self.message,
        }


def run_preflight(
    settings: ManagerSettings,
    canfar: CanfarOps,
    store: StateStore,
) -> PreflightReport:
    auth = canfar.auth_status()
    if not auth.authenticated:
        return PreflightReport(
            passed=False,
            manager_ip=manager_pod_ip(),
            worker_ip=None,
            worker_to_manager=[],
            manager_to_worker=[],
            probe_session_id=None,
            message=auth.message or "CANFAR authentication required",
        )

    manager_ip = manager_pod_ip()
    ports = ray_probe_ports()
    tag_safe = time.strftime("%Y%m%d%H%M%S")
    probe_name = f"ray-preflight-{settings.cluster_id}-{tag_safe}"[:60]

    if not _wait_manager_ports(manager_ip, ports, timeout_seconds=90):
        report = PreflightReport(
            passed=False,
            manager_ip=manager_ip,
            worker_ip=None,
            worker_to_manager=[],
            manager_to_worker=[],
            probe_session_id=None,
            message=f"Ray ports not reachable on manager {manager_ip} ({ports})",
        )
        store.log_event("preflight_done", **report.as_dict())
        _persist_preflight(store, settings, report)
        return report

    store.log_event("preflight_start", manager_ip=manager_ip, probe_name=probe_name)

    probe_id: str | None = None
    try:
        launch = canfar.create_headless(
            name=probe_name,
            image=settings.probe_image,
            cores=1,
            ram=2,
            env={
                "RAY_NETWORK_PROBE": "1",
                "PROBE_MANAGER_IP": manager_ip,
                "PROBE_PORTS": ports,
            },
        )[0]
    except RuntimeError as exc:
        report = PreflightReport(
            passed=False,
            manager_ip=manager_ip,
            worker_ip=None,
            worker_to_manager=[],
            manager_to_worker=[],
            probe_session_id=None,
            message=str(exc),
        )
        store.log_event("preflight_done", **report.as_dict())
        _persist_preflight(store, settings, report)
        return report

    probe_id = launch.session_id
    try:
        status = canfar.wait_for_status(
            probe_id,
            target={"Succeeded", "Completed", "Running"},
            timeout_seconds=settings.preflight_timeout_seconds,
        )

        # Running is OK — probe exits quickly; wait for terminal if still running.
        if status == "Running":
            status = canfar.wait_for_status(
                probe_id,
                target={"Succeeded", "Completed", "Failed", "Error"},
                timeout_seconds=min(120, settings.preflight_timeout_seconds),
            )

        logs = canfar.session_logs(probe_id)
        parsed = parse_probe_logs(logs)
        worker_ip = parsed.get("worker_ip")
        worker_checks = parsed.get("checks") or []
        probe_ok = parsed.get("result") == "PASS" and status in {
            "Succeeded",
            "Completed",
        }

        mgr_checks: list[dict[str, str]] = []
        if probe_ok and worker_ip:
            sample_ports = [
                int(os.environ.get("RAY_NODE_MANAGER_PORT", "6380")),
                int(os.environ.get("RAY_OBJECT_MANAGER_PORT", "6381")),
            ]
            mgr_checks = manager_to_worker_probe(manager_ip, worker_ip, sample_ports)

        message = None
        if not probe_ok:
            message = f"probe status={status} result={parsed.get('result')}"
        if probe_ok and mgr_checks and not all(c["result"] == "PASS" for c in mgr_checks):
            note = "manager->worker sample checks failed (non-fatal for preflight)"
            message = f"{message}; {note}" if message else note

        report = PreflightReport(
            passed=probe_ok,
            manager_ip=manager_ip,
            worker_ip=worker_ip,
            worker_to_manager=worker_checks,
            manager_to_worker=mgr_checks,
            probe_session_id=probe_id,
            message=message,
        )
        store.log_event("preflight_done", **report.as_dict())
        _persist_preflight(store, settings, report)
        return report
    finally:
        if probe_id:
            canfar.destroy(probe_id)


def _wait_manager_ports(ip: str, ports_csv: str, *, timeout_seconds: int) -> bool:
    port_list = [int(p.strip()) for p in ports_csv.split(",") if p.strip()]
    if not port_list:
        return False
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if all(_tcp_reachable(ip, port) for port in port_list):
            return True
        time.sleep(2)
    return False


def _tcp_reachable(ip: str, port: int, timeout: float = 3.0) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True
    except OSError:
        return False


def _persist_preflight(store: StateStore, settings: ManagerSettings, report: PreflightReport) -> None:
    from ray_cluster import ray_address

    state = store.load()
    if state is None:
        state = ClusterState(
            cluster_id=settings.cluster_id,
            manager_ip=report.manager_ip,
            ray_address=ray_address(),
        )
    state.preflight = report.as_dict()
    store.save(state)
