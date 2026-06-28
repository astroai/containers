#!/bin/bash -e
# Verify Ray manager contributed UI and JSON endpoints locally.

set -o pipefail

REGISTRY="${REGISTRY:-images.canfar.net}"
OWNER="${OWNER:-astroai}"
TAG="${BUILD_TAG:-local}"
NETWORK="ray-ui-test-$$"
FAKE_ARC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"
FAILURES=0

MGR="${REGISTRY}/${OWNER}/ray-manager:${TAG}"

cleanup() {
    docker rm -f ray-ui-test 2>/dev/null || true
    docker network rm "${NETWORK}" 2>/dev/null || true
    rm -rf "${FAKE_ARC}" "${FAKE_SCRATCH}"
}
trap cleanup EXIT

mkdir -p "${FAKE_ARC}/home/testuser" "${FAKE_SCRATCH}"
chmod -R a+rwX "${FAKE_ARC}" "${FAKE_SCRATCH}"
docker network create "${NETWORK}" >/dev/null

docker run -d --name ray-ui-test \
    --network "${NETWORK}" --shm-size=1g \
    -u "$(id -u):$(id -g)" \
    -e HOME=/arc/home/testuser -e USER=testuser \
    -e RAY_CLUSTER_ID=ui-test -e RAY_VERSION_EXPECTED=2.43.0 \
    -v "${FAKE_ARC}:/arc" -v "${FAKE_SCRATCH}:/scratch" \
    "${MGR}" >/dev/null

deadline=$((SECONDS + 120))
while (( SECONDS < deadline )); do
    docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
        -fsS "http://ray-ui-test:5000/readyz" >/dev/null 2>&1 && break
    sleep 2
done

check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  ok  %s\n' "${label}"
    else
        printf '  FAIL %s\n' "${label}" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

BASE="http://ray-ui-test:5000"
HTML="$(docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 -fsS "${BASE}/")"

echo "Ray manager UI verification"
echo "==========================="

check "HTML title" grep -q "CANFAR Ray Manager" <<< "${HTML}"
check "create cluster form" grep -q 'action="/actions/create-cluster"' <<< "${HTML}"
check "preflight action" grep -q 'action="/actions/preflight"' <<< "${HTML}"
check "stop cluster action" grep -q 'action="/actions/stop-cluster"' <<< "${HTML}"
check "clean orphans action" grep -q 'action="/actions/clean-orphans"' <<< "${HTML}"
check "auth status JSON" docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
    -fsS "${BASE}/api/v1/auth/status" | grep -q '"authenticated"'
check "status JSON" docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
    -fsS "${BASE}/api/v1/status" | grep -q '"ray_address"'
check "preflight POST" docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
    -fsS -o /dev/null -w '%{http_code}' -X POST "${BASE}/actions/preflight" | grep -qE '303|200'
check "reconcile POST" docker run --rm --network "${NETWORK}" curlimages/curl:8.5.0 \
    -fsS -o /dev/null -w '%{http_code}' -X POST "${BASE}/actions/reconcile" | grep -q '303'

echo ""
if [[ "${FAILURES}" -eq 0 ]]; then
    echo "Ray manager UI checks passed."
    exit 0
fi
echo "${FAILURES} UI check(s) failed." >&2
exit 1
