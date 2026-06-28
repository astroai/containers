"""Runtime settings for the Ray manager (env-driven)."""

from __future__ import annotations

import os
import socket
from dataclasses import dataclass


@dataclass(frozen=True)
class ManagerSettings:
    cluster_id: str
    ray_version: str
    ray_head_port: int
    worker_image: str
    probe_image: str
    scratch_dir: str
    heartbeat_timeout_seconds: int
    worker_launch_timeout_seconds: int
    preflight_timeout_seconds: int

    @classmethod
    def from_env(cls) -> ManagerSettings:
        tag = os.environ.get("RAY_IMAGE_TAG", os.environ.get("BUILD_TAG", "latest"))
        registry = os.environ.get("REGISTRY", "images.canfar.net")
        owner = os.environ.get("OWNER", "astroai")
        default_worker = f"{registry}/{owner}/ray-worker-cpu:{tag}"
        return cls(
            cluster_id=os.environ.get("RAY_CLUSTER_ID", "default"),
            ray_version=os.environ.get("RAY_VERSION_EXPECTED", "2.43.0"),
            ray_head_port=int(os.environ.get("RAY_HEAD_PORT", "6379")),
            worker_image=os.environ.get("RAY_WORKER_IMAGE", default_worker),
            probe_image=os.environ.get("RAY_PROBE_IMAGE", default_worker),
            scratch_dir=os.environ.get("TMP_SCRATCH_DIR", "/scratch"),
            heartbeat_timeout_seconds=int(
                os.environ.get("RAY_MANAGER_HEARTBEAT_TIMEOUT_SECONDS", "120")
            ),
            worker_launch_timeout_seconds=int(
                os.environ.get("RAY_WORKER_LAUNCH_TIMEOUT_SECONDS", "900")
            ),
            preflight_timeout_seconds=int(
                os.environ.get("RAY_PREFLIGHT_TIMEOUT_SECONDS", "600")
            ),
        )


def manager_pod_ip() -> str:
    explicit = os.environ.get("RAY_NODE_IP_ADDRESS", "").strip()
    if explicit:
        return explicit.split()[0]
    try:
        import subprocess

        out = subprocess.run(
            ["hostname", "-i"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        ip = out.stdout.strip().split()[0]
        if ip and ip != "127.0.0.1":
            return ip
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, IndexError):
        pass
    return socket.gethostbyname(socket.gethostname())


def ray_probe_ports() -> str:
    ports = [
        os.environ.get("RAY_HEAD_PORT", "6379"),
        os.environ.get("RAY_NODE_MANAGER_PORT", "6380"),
        os.environ.get("RAY_OBJECT_MANAGER_PORT", "6381"),
    ]
    return ",".join(ports)
