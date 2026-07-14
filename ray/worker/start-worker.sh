#!/bin/bash -e
# Ray worker entrypoint — env contract in docs/RAY.md.

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

# CANFAR persistent storage: use /arc/home/$USER (or $HOME when already set there),
# not the /arc mount root. Team data lives under /arc/projects/<group>/ (POSIX ACL).
_session_user="${USER:-$(id -un)}"
_canfar_home="/arc/home/${_session_user}"
if [[ -d "${_canfar_home}" && -w "${_canfar_home}" ]]; then
    export HOME="${_canfar_home}"
elif [[ -n "${HOME:-}" && -d "${HOME}" && -w "${HOME}" ]]; then
    :
else
    echo "WARN: ${_canfar_home} not writable — shared /arc/home unavailable; heartbeat monitor disabled" >&2
    echo "  (CANFAR mounts user data at /arc/home/\$USER or /arc/projects/<group>/, not /arc root)" >&2
    export RAY_SKIP_HEARTBEAT=1
fi

if [[ "${RAY_SKIP_HEARTBEAT:-}" != "1" ]]; then
    case "${RAY_MANAGER_HEARTBEAT_PATH}" in
        /arc/home/*) ;;
        *)
            echo "WARN: heartbeat path must be under /arc/home/<user> (got ${RAY_MANAGER_HEARTBEAT_PATH}); disabling monitor" >&2
            export RAY_SKIP_HEARTBEAT=1
            ;;
    esac
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
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        die "RAY_WORKER_GPUS=${RAY_WORKER_GPUS} but nvidia-smi not found — launch workers with CANFAR gpu=${RAY_WORKER_GPUS}"
    fi
    gpu_visible="$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ' || true)"
    if [[ "${gpu_visible}" -lt "${RAY_WORKER_GPUS}" ]]; then
        die "RAY_WORKER_GPUS=${RAY_WORKER_GPUS} but nvidia-smi reports ${gpu_visible} GPU(s)"
    fi
    ray_args+=(--num-gpus="${RAY_WORKER_GPUS}")
fi

export RAY_spill_dir="${RAY_SPILL_DIR}"

if [[ "${RAY_SKIP_HEARTBEAT:-}" == "1" ]]; then
    echo "Skipping manager heartbeat monitor (no shared /arc/home for this session)" >&2
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
