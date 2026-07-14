#!/bin/bash -e
# Skaha entrypoint — Ray head + manager UI on port 5000.

set -o pipefail

if [[ -f /etc/profile.d/astroai.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/astroai.sh
fi

export RAY_CLUSTER_ID="${RAY_CLUSTER_ID:-}"
if [[ -z "${RAY_CLUSTER_ID}" ]]; then
    # Bind state to this manager session so /arc/home does not reuse another
    # pod's clusters/default leftovers across contributed manager launches.
    _sid="${skaha_sessionid:-${SKAHA_SESSIONID:-}}"
    if [[ -n "${_sid}" ]]; then
        export RAY_CLUSTER_ID="mgr-${_sid}"
    else
        export RAY_CLUSTER_ID="default"
    fi
fi
# Jobs / Dashboard API is local to this pod — RayExecutor() reads this.
export ASTROAI_RAY_JOBS_ADDRESS="${ASTROAI_RAY_JOBS_ADDRESS:-http://127.0.0.1:8265}"
# shellcheck disable=SC1091
source /opt/astroai/lib/ray-version.sh
export RAY_VERSION_EXPECTED="$(ray_version_expected)"
export RAY_HEAD_PORT="${RAY_HEAD_PORT:-6379}"
export RAY_IMAGE_TAG="${RAY_IMAGE_TAG:-${BUILD_TAG:-${TAG:-local}}}"
export RAY_NODE_IP_ADDRESS="${RAY_NODE_IP_ADDRESS:-$(hostname -i | awk '{print $1}')}"

state_dir="${HOME}/.astroai/ray/clusters/${RAY_CLUSTER_ID}"
mkdir -p "${state_dir}"
export RAY_MANAGER_HEARTBEAT_PATH="${state_dir}/manager-heartbeat"
touch "${RAY_MANAGER_HEARTBEAT_PATH}"

(while true; do touch "${RAY_MANAGER_HEARTBEAT_PATH}"; sleep 5; done) &

echo "CANFAR Ray Manager starting (cluster ${RAY_CLUSTER_ID})"
exec python -m uvicorn app:app --host 0.0.0.0 --port 5000 --app-dir /opt/astroai/ray-manager
