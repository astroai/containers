#!/bin/bash -e
# Milestone C local test: state persistence, reconcile, cluster stop.
# Two-worker join on CANFAR: scripts/test-canfar-ray.sh

set -o pipefail

REGISTRY="${REGISTRY:-images.canfar.net}"
OWNER="${OWNER:-astroai}"
TAG="${BUILD_TAG:-local}"
NETWORK="canfar-ray-cluster-$$"
FAKE_ARC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"
CLUSTER_ID="local-cluster"
FAILURES=0

MGR="${REGISTRY}/${OWNER}/ray-manager:${TAG}"
WRK="${REGISTRY}/${OWNER}/ray-worker-cpu:${TAG}"

cleanup() {
    kill "${HEARTBEAT_PID:-}" 2>/dev/null || true
    docker rm -f "ray-mgr-${CLUSTER_ID}" "ray-wrk-${CLUSTER_ID}-1" 2>/dev/null || true
    docker network rm "${NETWORK}" 2>/dev/null || true
    rm -rf "${FAKE_ARC}" "${FAKE_SCRATCH}"
}
trap cleanup EXIT

mkdir -p "${FAKE_ARC}/home/testuser/.canfar-ray/clusters/${CLUSTER_ID}" "${FAKE_SCRATCH}/ray/${CLUSTER_ID}"
chmod -R a+rwX "${FAKE_ARC}" "${FAKE_SCRATCH}"
HOME="/arc/home/testuser"
HEARTBEAT="${HOME}/.canfar-ray/clusters/${CLUSTER_ID}/manager-heartbeat"
STATE_FILE="${FAKE_ARC}/home/testuser/.canfar-ray/clusters/${CLUSTER_ID}/state.json"

docker network create "${NETWORK}" >/dev/null

echo "Cluster state + reconcile test"
echo "=============================="

docker run -d --name "ray-mgr-${CLUSTER_ID}" \
    --network "${NETWORK}" --shm-size=1g \
    -u "$(id -u):$(id -g)" \
    -e HOME="${HOME}" -e USER=testuser \
    -e RAY_CLUSTER_ID="${CLUSTER_ID}" -e RAY_VERSION_EXPECTED=2.43.0 \
    -v "${FAKE_ARC}:/arc" -v "${FAKE_SCRATCH}:/scratch" \
    "${MGR}" >/dev/null

deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
    docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
        -fsS "http://ray-mgr-${CLUSTER_ID}:5000/readyz" >/dev/null 2>&1 && break
    sleep 2
done

HEAD_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "ray-mgr-${CLUSTER_ID}")"
touch "${FAKE_ARC}/home/testuser/.canfar-ray/clusters/${CLUSTER_ID}/manager-heartbeat"
(while true; do touch "${FAKE_ARC}/home/testuser/.canfar-ray/clusters/${CLUSTER_ID}/manager-heartbeat"; sleep 2; done) &
HEARTBEAT_PID=$!

docker run -d --name "ray-wrk-${CLUSTER_ID}-1" \
    --network "${NETWORK}" --shm-size=1g \
    -u "$(id -u):$(id -g)" \
    -e HOME="${HOME}" -e USER=testuser \
    -e RAY_CLUSTER_ID="${CLUSTER_ID}" \
    -e RAY_HEAD_IP="${HEAD_IP}" -e RAY_HEAD_PORT=6379 \
    -e RAY_VERSION_EXPECTED=2.43.0 \
    -e RAY_WORKER_CPUS=1 -e RAY_WORKER_GPUS=0 \
    -e RAY_SPILL_DIR="/scratch/ray/${CLUSTER_ID}/w1" \
    -e RAY_MANAGER_HEARTBEAT_PATH="${HEARTBEAT}" \
    -e RAY_MANAGER_HEARTBEAT_TIMEOUT_SECONDS=120 \
    -v "${FAKE_ARC}:/arc" -v "${FAKE_SCRATCH}:/scratch" \
    "${WRK}" >/dev/null

WRK_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "ray-wrk-${CLUSTER_ID}-1")"
echo "Manager ${HEAD_IP} · worker ${WRK_IP}"

echo "Waiting for worker to join Ray..."
deadline=$((SECONDS + 90))
while (( SECONDS < deadline )); do
    NODES="$(docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
        -fsS "http://ray-mgr-${CLUSTER_ID}:5000/api/v1/status" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('ray_nodes_alive',0))" 2>/dev/null || echo 0)"
    if [[ "${NODES}" -ge 2 ]]; then
        echo "Ray nodes alive: ${NODES}"
        break
    fi
    sleep 3
done
if [[ "${NODES:-0}" -lt 2 ]]; then
    echo "Worker did not join Ray within timeout (nodes=${NODES:-0})." >&2
    FAILURES=$((FAILURES + 1))
fi

python3 - "${STATE_FILE}" "${CLUSTER_ID}" "${HEAD_IP}" "${WRK_IP}" <<'PY'
import json, sys
from datetime import datetime, timezone
path, cluster_id, head_ip, w1 = sys.argv[1:5]
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
payload = {
    "cluster_id": cluster_id,
    "name": cluster_id,
    "manager_ip": head_ip,
    "ray_address": f"{head_ip}:6379",
    "phase": "Running",
    "worker_count": 2,
    "min_joined": 1,
    "partial_policy": "accept_partial",
    "preflight": {"passed": True},
    "workers": [{
        "session_id": "local-w1",
        "name": "ray-w-1",
        "phase": "Ray Joining",
        "canfar_status": "Running",
        "ray_joined": False,
        "worker_ip": w1,
        "cores": 1, "ram_gb": 4, "gpus": 0,
        "created_at": now, "updated_at": now,
        "last_error": None, "ray_node_id": None,
    }],
    "updated_at": now,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2)
    fh.write("\n")
PY

REC_JSON="$(docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
    -fsS --max-time 60 -X POST "http://ray-mgr-${CLUSTER_ID}:5000/api/v1/cluster/reconcile")"
JOINED="$(printf '%s' "${REC_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('joined_workers',0))")"
echo "Joined workers: ${JOINED}"
[[ "${JOINED}" -ge 1 ]] || FAILURES=$((FAILURES + 1))

STOP_JSON="$(docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
    -fsS --max-time 60 -X POST "http://ray-mgr-${CLUSTER_ID}:5000/api/v1/cluster/stop")"
STOP_PHASE="$(printf '%s' "${STOP_JSON}" | python3 -c "import json,sys; print((json.load(sys.stdin).get('cluster') or {}).get('phase',''))")"
echo "Phase after stop: ${STOP_PHASE}"
[[ "${STOP_PHASE}" == "Stopped" ]] || FAILURES=$((FAILURES + 1))

PHASE_ON_DISK="$(python3 -c "import json; print(json.load(open('${STATE_FILE}')).get('phase',''))")"
echo "Phase on disk: ${PHASE_ON_DISK}"
[[ "${PHASE_ON_DISK}" == "Stopped" ]] || FAILURES=$((FAILURES + 1))

if [[ "${FAILURES}" -eq 0 ]]; then
    echo "Cluster state + reconcile test passed."
    exit 0
fi
echo "Cluster state + reconcile test failed." >&2
exit 1
