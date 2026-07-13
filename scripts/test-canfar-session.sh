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
#
# Environment:
#   REGISTRY, OWNER, CANFAR_TEST_TIMEOUT (default 900)

IMAGE="${1:?image name required (webterm|notebook|vscode|marimo|ray-manager)}"
TAG="${2:-${TAG:-latest}}"
OWNER="${OWNER:-astroai}"
REGISTRY="${REGISTRY:-images.canfar.net}"
TIMEOUT="${CANFAR_TEST_TIMEOUT:-900}"
FULL_IMAGE="${REGISTRY}/${OWNER}/${IMAGE}:${TAG}"
TAG_SAFE="$(printf '%s' "${TAG}" | tr '.:/+' '-' | tr -cd 'a-zA-Z0-9-')"
SESSION_NAME="astroai-sess-${IMAGE}-${TAG_SAFE}-$(date -u +%Y%m%d%H%M%S)"
SESSION_ID=""
FAILURES=0

case "${IMAGE}" in
    notebook) KIND=notebook ;;
    *)        KIND=contributed ;;
esac

cleanup() {
    if [[ -n "${SESSION_ID:-}" ]]; then
        echo ""
        echo "Deleting test session ${SESSION_ID}..."
        canfar delete --force "${SESSION_ID}" 2>/dev/null || true
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

CREATE_OUT="$(canfar create --name "${SESSION_NAME}" --cpu "${CANFAR_TEST_CPU:-1}" \
    --memory "${CANFAR_TEST_MEMORY:-2}" "${KIND}" "${FULL_IMAGE}" 2>&1)" || {
    echo "${CREATE_OUT}" >&2
    echo "Failed to create ${KIND} session." >&2
    exit 1
}
echo "${CREATE_OUT}"

SESSION_ID="$(
    printf '%s\n' "${CREATE_OUT}" \
        | tr -d '\r' \
        | tr '\n' ' ' \
        | sed -n 's/.*(ID:[[:space:]]*\([^)]*\)).*/\1/p' \
        | awk '{print $1}'
)"
if [[ -z "${SESSION_ID}" ]]; then
    echo "Could not parse session ID." >&2
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

# Give the app a few seconds after Running for health.
sleep 15
HTTP_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 30 "${URL}" || echo 000)"
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
