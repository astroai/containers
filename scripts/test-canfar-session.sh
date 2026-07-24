#!/bin/bash -e
# Interactive-session smoke on CANFAR (contributed / notebook).
#
# Use when headless Skaha jobs stay Pending forever — contributed and notebook
# kinds still schedule. Verifies: create → Running → connectURL HTTP healthy.
#
# Usage:
#   ./scripts/test-canfar-session.sh webterm 26.07
#   ./scripts/test-canfar-session.sh notebook 26.07
#   ./scripts/test-canfar-session.sh vscode 26.07
#   ./scripts/test-canfar-session.sh marimo 26.07
#   ./scripts/test-canfar-session.sh openresearch 26.07
#
# Environment:
#   REGISTRY, OWNER, CANFAR_TEST_TIMEOUT (default 900)

IMAGE="${1:?image name required (webterm|notebook|vscode|marimo|openresearch|openworker|ray-manager)}"
TAG="${2:-${TAG:-latest}}"
OWNER="${OWNER:-astroai}"
REGISTRY="${REGISTRY:-images.canfar.net}"
TIMEOUT="${CANFAR_TEST_TIMEOUT:-900}"
# canfar create can time out client-side while Skaha still accepts the session
# (especially on cold image pulls). Cap at the CLI max (≤300s); the wait loop
# below still uses TIMEOUT for Running/HTTP readiness.
# CLI rejects values >300 (pydantic le=300); clamp so a large wait TIMEOUT never breaks create.
_raw_ct="${CANFAR_TIMEOUT:-300}"
if [[ "${_raw_ct}" -gt 300 ]]; then
    echo "Warning: CANFAR_TIMEOUT=${_raw_ct} exceeds CLI max 300; clamping." >&2
    _raw_ct=300
fi
export CANFAR_TIMEOUT="${_raw_ct}"
FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE}:${TAG}"
TAG_SAFE="$(printf '%s' "${TAG}" | tr '.:/+' '-' | tr -cd 'a-zA-Z0-9-')"
SESSION_NAME="astroai-sess-${IMAGE}-${TAG_SAFE}-$(date -u +%Y%m%d%H%M%S)"
SESSION_ID=""
FAILURES=0

case "${IMAGE}" in
    notebook) KIND=notebook ;;
    *)        KIND=contributed ;;
esac

# Ray manager runs Ray head + Dashboard — needs ≥8 GiB (see RAY.md / OPERATORS).
CPU="${CANFAR_TEST_CPU:-1}"
MEMORY="${CANFAR_TEST_MEMORY:-2}"
if [[ "${IMAGE}" == "ray-manager" ]]; then
    CPU="${CANFAR_TEST_CPU:-2}"
    MEMORY="${CANFAR_TEST_MEMORY:-8}"
fi

cleanup() {
    if [[ -n "${SESSION_ID:-}" ]]; then
        echo ""
        echo "Deleting test session ${SESSION_ID}..."
        canfar delete --force "${SESSION_ID}" 2>/dev/null || true
    fi
    # Belt-and-braces: kill any session still matching SESSION_NAME — covers the
    # rare case where both the (ID:...) parser and the name probe above missed
    # (e.g. Skaha catalog race) and an orphan would otherwise stay alive and
    # consume the user's 3-session quota.
    local orphan_id
    orphan_id="$(canfar ps -a --json 2>/dev/null | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
for m in ('[', '{'):
    i = raw.find(m)
    if i >= 0:
        raw = raw[i:]
        break
try:
    rows = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
if isinstance(rows, dict):
    rows = [rows]
for r in rows:
    if r.get('name') == sys.argv[1]:
        print(r.get('id') or '')
        break
" "${SESSION_NAME}" 2>/dev/null || true)"
    if [[ -n "${orphan_id}" && "${orphan_id}" != "${SESSION_ID:-}" ]]; then
        echo "Deleting orphan session ${orphan_id} (name match)..."
        canfar delete --force "${orphan_id}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

connect_url_for() {
    local sid="$1"
    canfar info "${sid}" 2>/dev/null | python3 -c '
import re, sys
text = sys.stdin.read()
m = re.search(r"Connect URL\s+(\S+)", text)
print(m.group(1) if m else "")
'
}

echo "CANFAR ${KIND} session smoke"
echo "  image:   ${FULL_IMAGE}"
echo "  name:    ${SESSION_NAME}"
echo "  timeout: ${TIMEOUT}s"
echo ""

if ! canfar auth show >/dev/null 2>&1; then
    echo "canfar is not authenticated. Run: canfar auth login" >&2
    exit 1
fi

# Capture create output without `|| \` under `set -e` — failed creates often
# still land in Skaha, and fragile `||` continuations have mis-executed the
# canfar banner (`@canfar`) as a shell command when CREATE_OUT was replayed.
set +e
CREATE_OUT="$(canfar create --name "${SESSION_NAME}" --cpu "${CPU}" \
    --memory "${MEMORY}" "${KIND}" "${FULL_IMAGE}" 2>&1)"
CREATE_RC=$?
set -e
if [[ "${CREATE_RC}" -ne 0 ]]; then
    echo "Warning: canfar create exited ${CREATE_RC} — will probe by name." >&2
fi
printf '%s\n' "${CREATE_OUT}"

SESSION_ID="$(
    printf '%s\n' "${CREATE_OUT}" \
        | tr -d '\r' \
        | tr '\n' ' ' \
        | sed -n 's/.*(ID:[[:space:]]*\([^)]*\)).*/\1/p' \
        | awk '{print $1}'
)"
# canfar create's (ID:...) parser can miss on slow Skaha responses (the CLI
# may even exit non-zero with "No session IDs returned"), but Skaha usually
# still accepts the session. Probe by name as a fallback — mirrors
# test-canfar.sh / test-canfar-ray.sh so we never leave Skaha-created
# orphans behind that would consume the user's 3-session quota.
#
# Catalog lag is common after a client-side create timeout: retry the name
# probe with backoff before declaring failure.
resolve_session_id_by_name() {
    canfar ps -a --json 2>/dev/null | python3 -c "
import json, sys
raw = sys.stdin.read().strip()
for m in ('[', '{'):
    i = raw.find(m)
    if i >= 0:
        raw = raw[i:]
        break
try:
    rows = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
if isinstance(rows, dict):
    rows = [rows]
for r in rows:
    if r.get('name') == sys.argv[1]:
        print(r.get('id') or '')
        break
" "${SESSION_NAME}" 2>/dev/null || true
}
if [[ -z "${SESSION_ID}" ]]; then
    for _try in 1 2 3 4 5 6; do
        SESSION_ID="$(resolve_session_id_by_name)"
        if [[ -n "${SESSION_ID}" ]]; then
            echo "Resolved session ID via name probe (attempt ${_try}): ${SESSION_ID}"
            break
        fi
        sleep $(( _try * 2 ))
    done
fi
if [[ -z "${SESSION_ID}" ]]; then
    echo "Could not resolve session ID for ${SESSION_NAME}." >&2
    exit 1
fi

echo "Session ID: ${SESSION_ID}"
echo "Waiting for Running..."

deadline=$((SECONDS + TIMEOUT))
status=""
while (( SECONDS < deadline )); do
    status="$(canfar ps --json 2>/dev/null | python3 -c "
import json, sys
sid = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
for marker in ('[', '{'):
    idx = raw.find(marker)
    if idx >= 0:
        raw = raw[idx:]
        break
rows = json.loads(raw)
if isinstance(rows, dict):
    rows = [rows]
for row in rows:
    if row.get('id') == sid:
        print(row.get('status', ''))
        break
" "${SESSION_ID}" 2>/dev/null || true)"
    case "${status}" in
        Running)
            echo "Session Running."
            break
            ;;
        Failed|Error|Terminating|Succeeded|Completed)
            echo "Unexpected terminal status: ${status}" >&2
            break
            ;;
    esac
    sleep 10
done

if [[ "${status}" != "Running" ]]; then
    echo "Session did not become Running (status=${status:-timeout})." >&2
    canfar logs "${SESSION_ID}" 2>&1 | tail -40 || true
    FAILURES=$((FAILURES + 1))
    exit ${FAILURES}
fi

URL="$(connect_url_for "${SESSION_ID}")"
if [[ -z "${URL}" ]]; then
    echo "No connect URL on Running session." >&2
    FAILURES=$((FAILURES + 1))
    exit ${FAILURES}
fi
echo "Connect URL: ${URL}"

# Give the app time after Running for health (Ray manager starts Ray head first).
_http_deadline=$((SECONDS + ${SMOKE_HTTP_WAIT:-120}))
HTTP_CODE="000"
while (( SECONDS < _http_deadline )); do
    HTTP_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 30 "${URL}" || true)"
    case "${HTTP_CODE}" in
        200|301|302|303|307|308) break ;;
    esac
    sleep 5
done
echo "HTTP ${HTTP_CODE} from connect URL"

case "${HTTP_CODE}" in
    200|301|302|303|307|308)
        echo "CANFAR ${KIND} session smoke passed for ${FULL_IMAGE}."
        ;;
    *)
        echo "HTTP check failed (${HTTP_CODE})." >&2
        canfar logs "${SESSION_ID}" 2>&1 | tail -60 || true
        FAILURES=$((FAILURES + 1))
        ;;
esac

exit ${FAILURES}
