#!/bin/bash -e
# Local smoke test: run an AstroAI session image as a non-root user.
#
# Usage:
#   ./scripts/test-local.sh webterm [port]
#   ./scripts/test-local.sh notebook [port]   # defaults to 8888

IMAGE="${1:-webterm}"
PORT="${2:-}"
OWNER="${OWNER:-astroai}"
REGISTRY="${REGISTRY:-images.canfar.net}"
TAG="${TAG:-local}"
SESSION_ID="${SESSION_ID:-test-session-001}"

FAKE_ARC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"
trap 'rm -rf "${FAKE_ARC}" "${FAKE_SCRATCH}"' EXIT

mkdir -p "${FAKE_ARC}/testuser"
FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE}:${TAG}"

if [[ "${IMAGE}" == "notebook" ]]; then
    PORT="${PORT:-8888}"
    CONTAINER_PORT=8888
    EXTRA_ENV=(-e "JUPYTER_TOKEN=${SESSION_ID}")
    RUN_CMD=(/skaha/startup.sh "${SESSION_ID}")
else
    PORT="${PORT:-5000}"
    CONTAINER_PORT=5000
    EXTRA_ENV=(-e "skaha_sessionid=${SESSION_ID}")
    RUN_CMD=()
fi

echo "Running ${FULL_IMAGE} on http://127.0.0.1:${PORT}"
echo "  HOME=${FAKE_ARC}/testuser"
echo "  /scratch=${FAKE_SCRATCH}"
echo "  session=${SESSION_ID}"

docker run --rm -it \
    -u "$(id -u):$(id -g)" \
    -e HOME="${FAKE_ARC}/testuser" \
    -e USER=testuser \
    "${EXTRA_ENV[@]}" \
    -v "${FAKE_ARC}/testuser:${FAKE_ARC}/testuser" \
    -v "${FAKE_SCRATCH}:/scratch" \
    -p "${PORT}:${CONTAINER_PORT}" \
    "${FULL_IMAGE}" \
    "${RUN_CMD[@]}"
