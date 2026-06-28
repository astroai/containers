#!/bin/bash -e
# Ray image layout checks.

set -o pipefail

REGISTRY="${REGISTRY:-images.canfar.net}"
OWNER="${OWNER:-astroai}"
TAG="${BUILD_TAG:-local}"
FAILURES=0

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

MGR="${REGISTRY}/${OWNER}/ray-manager:${TAG}"
WRK="${REGISTRY}/${OWNER}/ray-worker-cpu:${TAG}"

echo "Ray container verification"
echo "=========================="

check "ray-manager startup.sh" docker run --rm --entrypoint test "${MGR}" -x /skaha/startup.sh
check "ray-worker entrypoint" docker run --rm --entrypoint test "${WRK}" -x /opt/astroai/bin/start-ray-worker.sh
check "ray installed" docker run --rm --entrypoint python "${WRK}" -c "import ray; print(ray.__version__)"
check "ray version pin" docker run --rm --entrypoint python "${WRK}" -c "import ray; assert ray.__version__=='2.43.0'"
check "network probe script" docker run --rm --entrypoint test "${WRK}" -x /opt/astroai/bin/ray-network-probe.sh
check "canfar in manager" docker run --rm --entrypoint python "${MGR}" -c "import canfar"
check "manager app loads" docker run --rm --entrypoint python "${MGR}" -c "import sys; sys.path.insert(0,'/opt/astroai/ray-manager'); import app"
check "preflight module" docker run --rm --entrypoint python "${MGR}" -c "
import sys
sys.path.insert(0,'/opt/astroai/ray-manager')
import preflight
src = open('/opt/astroai/ray-manager/preflight.py').read()
assert 'passed=probe_ok' in src, 'preflight must assign passed from probe_ok'
"
check "worker image tag env" bash -c "docker run --rm --entrypoint printenv \"${MGR}\" RAY_IMAGE_TAG | grep -qx \"${TAG}\""
check "worker rejects missing env" bash -c "! docker run --rm \"${WRK}\" 2>/dev/null"

echo ""
if [[ "${FAILURES}" -eq 0 ]]; then
    echo "All container checks passed."
    exit 0
fi
echo "${FAILURES} check(s) failed." >&2
exit 1
