"""Ray head membership helpers."""

from __future__ import annotations

import json
import os
import subprocess
from typing import Any


def ray_address() -> str:
    from settings import manager_pod_ip

    port = os.environ.get("RAY_HEAD_PORT", "6379")
    return f"{manager_pod_ip()}:{port}"


def ray_running() -> bool:
    ray_bin = os.environ.get("RAY_BIN", "/opt/astroai/venv/ray/bin/ray")
    try:
        out = subprocess.run(
            [ray_bin, "status"],
            capture_output=True,
            text=True,
            check=True,
            timeout=15,
        )
        return "Started" in out.stdout or "node_" in out.stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return False


def list_ray_nodes() -> list[dict[str, Any]]:
    python_bin = os.environ.get("PYTHON_BIN", "/opt/astroai/venv/ray/bin/python")
    script = """
import json
import ray

ray.init(address=__import__("os").environ.get("RAY_ADDRESS"), ignore_reinit_error=True)
print(json.dumps(ray.nodes()))
"""
    env = os.environ.copy()
    env["RAY_ADDRESS"] = ray_address()
    try:
        out = subprocess.run(
            [python_bin, "-c", script],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
            env=env,
        )
        return json.loads(out.stdout.strip() or "[]")
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []


def parse_worker_ip_from_logs(logs: str) -> str | None:
    for line in logs.splitlines():
        if line.startswith("Worker ") and " joining " in line:
            parts = line.split()
            if len(parts) >= 2:
                return parts[1]
    return None


def live_worker_node_ips(nodes: list[dict[str, Any]] | None = None) -> set[str]:
    ips: set[str] = set()
    nodes = nodes if nodes is not None else list_ray_nodes()
    for node in nodes:
        if not node.get("Alive"):
            continue
        addr = str(node.get("NodeManagerAddress") or "")
        if addr:
            ips.add(addr.split(":")[0])
    return ips


def node_ip_to_id(nodes: list[dict[str, Any]] | None = None) -> dict[str, str]:
    mapping: dict[str, str] = {}
    nodes = nodes if nodes is not None else list_ray_nodes()
    for node in nodes:
        if not node.get("Alive"):
            continue
        addr = str(node.get("NodeManagerAddress") or "")
        if not addr:
            continue
        mapping[addr.split(":")[0]] = str(node.get("NodeID") or "")
    return mapping


def count_live_nodes(nodes: list[dict[str, Any]] | None = None) -> int:
    nodes = nodes if nodes is not None else list_ray_nodes()
    return sum(1 for node in nodes if node.get("Alive"))


def wait_for_node_count(
    *,
    minimum: int,
    timeout_seconds: int,
    poll_seconds: int = 5,
) -> int:
    import time

    deadline = time.monotonic() + timeout_seconds
    count = 0
    while time.monotonic() < deadline:
        count = count_live_nodes()
        if count >= minimum:
            return count
        time.sleep(poll_seconds)
    return count
