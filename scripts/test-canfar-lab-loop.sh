#!/bin/bash -e
# canfar-lab cold-start → save → resume loop inside astroai/base image.

set -o pipefail

REGISTRY="${REGISTRY:-images.canfar.net}"
OWNER="${OWNER:-astroai}"
TAG="${BUILD_TAG:-local}"
IMAGE="${REGISTRY}/${OWNER}/base:${TAG}"
FAKE_ARC="$(mktemp -d)"
FAKE_SRC="$(mktemp -d)"
FAKE_SCRATCH="$(mktemp -d)"

cleanup() {
    rm -rf "${FAKE_ARC}" "${FAKE_SRC}" "${FAKE_SCRATCH}"
}
trap cleanup EXIT

echo "canfar-lab save/resume loop (in ${IMAGE})"
echo "========================================"

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    echo "Image missing: ${IMAGE} — run make build/base BUILD_TAG=${TAG}" >&2
    exit 1
fi

mkdir -p "${FAKE_ARC}/testuser"
chmod -R a+rwX "${FAKE_ARC}" "${FAKE_SRC}" "${FAKE_SCRATCH}"

OUT="$(docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e HOME="${FAKE_ARC}/testuser" \
    -e USER=testuser \
    -e CANFAR_LAB_WORK_DIR=/srcdir \
    -e CANFAR_LAB_SCRATCH_DIR=/scratch \
    -v "${FAKE_ARC}/testuser:${FAKE_ARC}/testuser" \
    -v "${FAKE_SRC}:/srcdir" \
    -v "${FAKE_SCRATCH}:/scratch" \
    "${IMAGE}" \
    bash -lc '
set -e
source /etc/profile.d/astroai.sh
cd /srcdir

pixi init loopdemo --no-progress
cd loopdemo
canfar-lab env save loopdemo

# Fresh work tree (same HOME — simulates new session, same /arc/home)
rm -rf /srcdir/loopdemo
cd /srcdir
canfar-lab env resume loopdemo
test -f loopdemo/pixi.toml
canfar-lab doctor --json | head -1
echo LOOP_OK
' 2>&1)"

echo "${OUT}"

if printf '%s\n' "${OUT}" | grep -q LOOP_OK; then
    echo "canfar-lab loop test passed."
    exit 0
fi

echo "canfar-lab loop test failed." >&2
exit 1
