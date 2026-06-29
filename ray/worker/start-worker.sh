#!/bin/bash -e
# Ray worker entrypoint — env contract in docs/ray-build-plan.md §7.

set -o pipefail

if [[ "${RAY_NETWORK_PROBE:-}" == "1" ]]; then
    exec /opt/astroai/bin/ray-network-probe.sh
fi

RAY_BIN="${RAY_BIN:-/opt/astroai/venv/ray/bin/ray}"
PYTHON_BIN="${PYTHON_BIN:-/opt/astroai/venv/ray/bin/python}"

die() { echo "ERROR: $*" >&2; exit 1; }

require_var() {
    local name="$1"
    [[ -n "${!name:-}" ]] || die "missing required env: ${name}"
}

require_var RAY_CLUSTER_ID
require_var RAY_HEAD_IP
require_var RAY_HEAD_PORT
require_var RAY_VERSION_EXPECTED
require_var RAY_WORKER_CPUS
require_var RAY_SPILL_DIR
require_var RAY_MANAGER_HEARTBEAT_PATH
require_var RAY_MANAGER_HEARTBEAT_TIMEOUT_SECONDS

RAY_WORKER_GPUS="${RAY_WORKER_GPUS:-0}"

installed="$("${PYTHON_BIN}" -c 'import ray; print(ray.__version__)' 2>/dev/null || true)"
[[ "${installed}" == "${RAY_VERSION_EXPECTED}" ]] \
    || die "Ray version mismatch: installed=${installed} expected=${RAY_VERSION_EXPECTED}"

[[ -d /scratch && -w /scratch ]] || die "/scratch not writable"

if [[ -d /arc && -w /arc ]]; then
    ARC_WRITABLE=1
else
    ARC_WRITABLE=0
    echo "WARN: /arc not writable — headless session without shared ARC; heartbeat monitor disabled" >&2
    export RAY_SKIP_HEARTBEAT=1
fi

mkdir -p "${RAY_SPILL_DIR}"

worker_ip="$(hostname -i | awk '{print $1}')"
echo "Worker ${worker_ip} joining ${RAY_HEAD_IP}:${RAY_HEAD_PORT} (cluster ${RAY_CLUSTER_ID})"

if ! timeout 15 bash -c "echo >/dev/tcp/${RAY_HEAD_IP}/${RAY_HEAD_PORT}" 2>/dev/null; then
    die "cannot reach Ray head at ${RAY_HEAD_IP}:${RAY_HEAD_PORT}"
fi

ray_args=(
    --address="${RAY_HEAD_IP}:${RAY_HEAD_PORT}"
    --node-ip-address="${worker_ip}"
    --num-cpus="${RAY_WORKER_CPUS}"
    --block
)

if [[ "${RAY_WORKER_GPUS}" != "0" ]]; then
    ray_args+=(--num-gpus="${RAY_WORKER_GPUS}")
fi

export RAY_spill_dir="${RAY_SPILL_DIR}"

if [[ "${RAY_SKIP_HEARTBEAT:-}" == "1" ]]; then
    echo "Skipping manager heartbeat monitor (/arc unavailable on this session)" >&2
else
(
    while true; do
        if [[ ! -f "${RAY_MANAGER_HEARTBEAT_PATH}" ]]; then
            echo "Manager heartbeat missing: ${RAY_MANAGER_HEARTBEAT_PATH}" >&2
            exit 1
        fi
        age=$(( $(date +%s) - $(stat -c %Y "${RAY_MANAGER_HEARTBEAT_PATH}") ))
        if (( age > RAY_MANAGER_HEARTBEAT_TIMEOUT_SECONDS )); then
            echo "Manager heartbeat stale (${age}s)" >&2
            exit 1
        fi
        sleep 10
    done
) &
watch_pid=$!
trap 'kill ${watch_pid} 2>/dev/null || true' EXIT
fi

"${RAY_BIN}" start "${ray_args[@]}"
