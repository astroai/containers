#!/bin/bash -e
# OpenResearch (orx) dashboard on port 5000 (CANFAR contributed).
# Upstream binds 127.0.0.1:4791; socat fronts 0.0.0.0:5000 for ingress.

source /cadc/common-init.sh

export ORX_NO_UPDATE_CHECK=1
export PATH="/opt/astroai/bin:${PATH}"

# orx persists local store under XDG data home.
mkdir -p "${XDG_DATA_HOME:-${HOME}/.local/share}/openresearch" \
    "${XDG_CONFIG_HOME:-${HOME}/.config}/openresearch" \
    "${XDG_CACHE_HOME:-${HOME}/.cache}/openresearch"

# Best-effort: drop OpenResearch skills into agent configs on /arc/home.
if command -v orx >/dev/null 2>&1; then
    orx --no-telemetry telemetry off >/dev/null 2>&1 || true
    orx --no-telemetry install-skills >/dev/null 2>&1 || true
fi

ORX_PORT="${ORX_PORT:-4791}"
PUBLIC_PORT="${ASTROAI_OPENRESEARCH_PORT:-5000}"

orx --no-telemetry up --port "${ORX_PORT}" --no-browser &
ORX_PID=$!

cleanup() {
    kill "${SOCAT_PID:-}" "${ORX_PID}" 2>/dev/null || true
    wait "${SOCAT_PID:-}" "${ORX_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait until orx is accepting connections.
for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${ORX_PORT}/" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "${ORX_PID}" 2>/dev/null; then
        echo "orx up exited early" >&2
        exit 1
    fi
    sleep 0.5
done

# CANFAR contributed ingress strips /session/contrib/<id>; serve at /.
# TCP proxy preserves HTTP, SSE, and websockets without a base-path.
socat \
    TCP-LISTEN:"${PUBLIC_PORT}",fork,reuseaddr,bind=0.0.0.0 \
    TCP:127.0.0.1:"${ORX_PORT}" &
SOCAT_PID=$!

# Exit when either process dies.
wait -n "${ORX_PID}" "${SOCAT_PID}"
exit $?
