#!/bin/bash -e
# OpenWorker browser UI + Python server on port 5000 (CANFAR contributed).
# No Tauri — path-rewriting proxy serves the Vite build and /v1|/ws API.

export ASTROAI_SESSION_KIND="${ASTROAI_SESSION_KIND:-openworker}"
source /cadc/common-init.sh
# shellcheck disable=SC1091
source /opt/astroai/lib/skaha-proxy.sh

export PATH="/opt/openworker/venv/bin:/opt/astroai/bin:${PATH}"
export ASTROAI_OPENWORKER_PORT="${ASTROAI_OPENWORKER_PORT:-5000}"
export OPENWORKER_PORT="${OPENWORKER_PORT:-8765}"
export ASTROAI_AGENT_WIZARD_PORT="${ASTROAI_AGENT_WIZARD_PORT:-4792}"
export OPENWORKER_UI_ROOT="${OPENWORKER_UI_ROOT:-/opt/openworker/gui}"

# Persist OpenWorker state on /arc/home when available.
mkdir -p \
    "${XDG_DATA_HOME:-${HOME}/.local/share}/openworker" \
    "${XDG_CONFIG_HOME:-${HOME}/.config}/openworker" \
    "${XDG_CACHE_HOME:-${HOME}/.cache}/openworker"

WORKDIR="${TMP_SRC_DIR:-/srcdir}"
mkdir -p "${WORKDIR}"

# Agent wizard — never block the main UI.
python3 /opt/astroai/lib/agent-wizard.py &
WIZARD_PID=$!

# Local agent server (browser talks via path proxy, not 127.0.0.1 from the client).
openworker-server --cwd "${WORKDIR}" --port "${OPENWORKER_PORT}" &
OW_PID=$!

cleanup() {
    kill "${PROXY_PID:-}" "${WIZARD_PID:-}" "${OW_PID:-}" 2>/dev/null || true
    wait "${PROXY_PID:-}" "${WIZARD_PID:-}" "${OW_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for _ in $(seq 1 90); do
    if curl -fsS "http://127.0.0.1:${OPENWORKER_PORT}/v1/health" >/dev/null 2>&1; then
        break
    fi
    if ! kill -0 "${OW_PID}" 2>/dev/null; then
        echo "openworker-server exited early" >&2
        exit 1
    fi
    sleep 0.5
done

if ! curl -fsS "http://127.0.0.1:${OPENWORKER_PORT}/v1/health" >/dev/null 2>&1; then
    echo "openworker-server did not become ready on :${OPENWORKER_PORT}" >&2
    exit 1
fi

python3 /opt/astroai/lib/openworker-canfar-proxy.py &
PROXY_PID=$!

wait -n "${OW_PID}" "${PROXY_PID}"
exit $?
