#!/bin/bash -e
# Local Ray cluster: manager + worker join + smoke task.

set -o pipefail

REGISTRY="${REGISTRY:-images.canfar.net}"
OWNER="${OWNER:-astroai}"
TAG="${BUILD_TAG:-local}"
NETWORK="canfar-ray-test-$$"
FAKE_ARC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"
CLUSTER_ID="local-test"
FAILURES=0

MGR="${REGISTRY}/${OWNER}/ray-manager:${TAG}"
WRK="${REGISTRY}/${OWNER}/ray-worker-cpu:${TAG}"

cleanup() {
    docker rm -f "ray-mgr-${CLUSTER_ID}" "ray-wrk-${CLUSTER_ID}" 2>/dev/null || true
    docker network rm "${NETWORK}" 2>/dev/null || true
    rm -rf "${FAKE_ARC}" "${FAKE_SCRATCH}"
}
trap cleanup EXIT

mkdir -p "${FAKE_ARC}/home/testuser" "${FAKE_SCRATCH}/ray/${CLUSTER_ID}"
chmod -R a+rwX "${FAKE_ARC}" "${FAKE_SCRATCH}"
HOME="/arc/home/testuser"
HEARTBEAT="${HOME}/.canfar-ray/clusters/${CLUSTER_ID}/manager-heartbeat"

docker network create "${NETWORK}" >/dev/null

echo "Starting Ray manager..."
docker run -d --name "ray-mgr-${CLUSTER_ID}" \
    --network "${NETWORK}" --shm-size=1g \
    -u "$(id -u):$(id -g)" \
    -e HOME="${HOME}" \
    -e USER=testuser \
    -e RAY_CLUSTER_ID="${CLUSTER_ID}" \
    -e RAY_VERSION_EXPECTED=2.43.0 \
    -v "${FAKE_ARC}:/arc" \
    -v "${FAKE_SCRATCH}:/scratch" \
    "${MGR}" >/dev/null

echo "Waiting for manager /readyz..."
deadline=$((SECONDS + 120))
ready=0
while (( SECONDS < deadline )); do
    if docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
        -fsS "http://ray-mgr-${CLUSTER_ID}:5000/readyz" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [[ "${ready}" -ne 1 ]]; then
    echo "Manager not ready:" >&2
    docker logs "ray-mgr-${CLUSTER_ID}" 2>&1 | tail -40 >&2
    exit 1
fi

HEAD_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "ray-mgr-${CLUSTER_ID}")"
echo "Manager pod IP: ${HEAD_IP}"

echo "Starting Ray worker (background)..."
docker run -d --name "ray-wrk-${CLUSTER_ID}" \
    --network "${NETWORK}" --shm-size=1g \
    -u "$(id -u):$(id -g)" \
    -e HOME="${HOME}" \
    -e USER=testuser \
    -e RAY_CLUSTER_ID="${CLUSTER_ID}" \
    -e RAY_HEAD_IP="${HEAD_IP}" \
    -e RAY_HEAD_PORT=6379 \
    -e RAY_VERSION_EXPECTED=2.43.0 \
    -e RAY_WORKER_CPUS=1 \
    -e RAY_WORKER_GPUS=0 \
    -e RAY_SPILL_DIR="/scratch/ray/${CLUSTER_ID}" \
    -e RAY_MANAGER_HEARTBEAT_PATH="${HEARTBEAT}" \
    -e RAY_MANAGER_HEARTBEAT_TIMEOUT_SECONDS=120 \
    -v "${FAKE_ARC}:/arc" \
    -v "${FAKE_SCRATCH}:/scratch" \
    "${WRK}" >/dev/null

echo "Waiting for worker to join Ray..."
deadline=$((SECONDS + 90))
NODES=0
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
    docker logs "ray-wrk-${CLUSTER_ID}" 2>&1 | tail -30 >&2
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "Running distributed smoke test from manager..."
docker cp examples/ray/distributed_smoke_test.py "ray-mgr-${CLUSTER_ID}:/tmp/smoke.py"
if docker exec "ray-mgr-${CLUSTER_ID}" python /tmp/smoke.py; then
    :
else
    FAILURES=$((FAILURES + 1))
fi

echo ""
if [[ "${FAILURES}" -eq 0 ]]; then
    echo "Local Ray cluster test passed."
    exit 0
fi
echo "Local Ray cluster test failed." >&2
exit 1
