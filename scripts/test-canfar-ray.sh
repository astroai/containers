#!/bin/bash -e
# Milestone B smoke test on CANFAR: contributed ray-manager + worker via session API.
#
# Requires: canfar CLI authenticated (canfar auth login) with config on /arc/home
# so the manager session inherits credentials.
#
# Usage:
#   ./scripts/test-canfar-ray.sh [tag]
#   RAY_MANAGER_URL=https://.../session/contributed/xyz ./scripts/test-canfar-ray.sh
#
# Environment:
#   REGISTRY, OWNER, CANFAR_TEST_TIMEOUT (default 1800)
#   CANFAR_REGISTRY__* / REGISTRY_USER — Harbor pull for worker image (see test-canfar.sh)

TAG="${1:-${TAG:-26.06}}"
OWNER="${OWNER:-astroai}"
REGISTRY="${REGISTRY:-images.canfar.net}"
TIMEOUT="${CANFAR_TEST_TIMEOUT:-1800}"
FULL_IMAGE="${REGISTRY}/${OWNER}/ray-manager:${TAG}"
TAG_SAFE="$(printf '%s' "${TAG}" | tr '.:/+' '-' | tr -cd 'a-zA-Z0-9-')"
SESSION_NAME="ray-mgr-test-${TAG_SAFE}-$(date -u +%Y%m%d%H%M%S)"
MANAGER_URL="${RAY_MANAGER_URL:-}"
SESSION_ID=""
FAILURES=0

maybe_registry_auth() {
    if [[ -n "${CANFAR_REGISTRY__USERNAME:-}" && -n "${CANFAR_REGISTRY__SECRET:-}" ]]; then
        export CANFAR_REGISTRY__URL="${CANFAR_REGISTRY__URL:-https://${REGISTRY}}"
        return 0
    fi
    if [[ -n "${REGISTRY_USER:-}" && -n "${REGISTRY_PASSWORD:-}" ]]; then
        export CANFAR_REGISTRY__USERNAME="${REGISTRY_USER}"
        export CANFAR_REGISTRY__SECRET="${REGISTRY_PASSWORD}"
        export CANFAR_REGISTRY__URL="${CANFAR_REGISTRY__URL:-https://${REGISTRY}}"
        return 0
    fi
}

load_docker_registry_auth() {
    local docker_cfg="${HOME}/.docker/config.json"
    [[ -f "${docker_cfg}" ]] || return 1

    local _creds=()
    mapfile -t _creds < <(
        python3 - "${REGISTRY}" "${docker_cfg}" <<'PY'
import base64
import json
import sys

registry, path = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
entry = cfg.get("auths", {}).get(registry, {})
if "auth" in entry:
    user, secret = base64.b64decode(entry["auth"]).decode().split(":", 1)
elif entry.get("username") and entry.get("password"):
    user, secret = entry["username"], entry["password"]
else:
    sys.exit(1)
if not user or not secret:
    sys.exit(1)
print(user)
print(secret)
PY
    ) || return 1
    [[ ${#_creds[@]} -ge 2 ]] || return 1

    export CANFAR_REGISTRY__USERNAME="${_creds[0]}"
    export CANFAR_REGISTRY__SECRET="${_creds[1]}"
    export CANFAR_REGISTRY__URL="${CANFAR_REGISTRY__URL:-https://${REGISTRY}}"
}

bootstrap_canfar_registry_on_arc() {
    if [[ -z "${CANFAR_REGISTRY__USERNAME:-}" || -z "${CANFAR_REGISTRY__SECRET:-}" ]]; then
        return 1
    fi

    local bootstrap_name="ray-regcfg-${TAG_SAFE}-$(date -u +%Y%m%d%H%M%S)"
    local base_image="${REGISTRY}/${OWNER}/base:${TAG}"
    local registry_url="${CANFAR_REGISTRY__URL:-https://${REGISTRY}}"
    local create_out="" bootstrap_id="" status=""

    echo "Persisting Harbor registry credentials to /arc/home via headless bootstrap..."
    create_out="$(canfar create --name "${bootstrap_name}" headless "${base_image}" \
        -e "REGISTRY_URL=${registry_url}" \
        -e "REGISTRY_USER=${CANFAR_REGISTRY__USERNAME}" \
        -e "REGISTRY_SECRET=${CANFAR_REGISTRY__SECRET}" \
        -- bash /opt/astroai/bin/bootstrap-canfar-registry.sh 2>&1)" || {
        echo "${create_out}" >&2
        return 1
    }

    bootstrap_id="$(printf '%s\n' "${create_out}" | sed -n 's/.*(ID:[[:space:]]*\([^)]*\)).*/\1/p' | awk '{print $1}')"
    [[ -n "${bootstrap_id}" ]] || bootstrap_id="$(canfar_ps_field name "${bootstrap_name}" id)"
    [[ -n "${bootstrap_id}" ]] || { echo "Could not parse bootstrap session ID." >&2; return 1; }

    local deadline=$((SECONDS + 600))
    while (( SECONDS < deadline )); do
        status="$(canfar_ps_field id "${bootstrap_id}" status)"
        case "${status}" in
            Succeeded|Completed) break ;;
            Failed|Error)
                echo "Bootstrap session failed (${status})." >&2
                canfar logs "${bootstrap_id}" 2>&1 | tail -30 >&2 || true
                canfar delete --force "${bootstrap_id}" 2>/dev/null || true
                return 1
                ;;
        esac
        sleep 5
    done
    canfar delete --force "${bootstrap_id}" 2>/dev/null || true
    if [[ "${status}" != "Succeeded" && "${status}" != "Completed" ]]; then
        echo "Bootstrap session timed out (status: ${status:-unknown})." >&2
        return 1
    fi
    echo "Registry credentials persisted for user ${CANFAR_REGISTRY__USERNAME}."
}

create_manager_session() {
    canfar create --name "${SESSION_NAME}" contributed "${FULL_IMAGE}" 2>&1
}

curl_auth=( )
if [[ -f "${HOME}/.ssl/cadcproxy.pem" ]]; then
    curl_auth=(--cert "${HOME}/.ssl/cadcproxy.pem")
elif [[ -n "${CANFAR_TOKEN:-}" ]]; then
    curl_auth=(-H "Authorization: Bearer ${CANFAR_TOKEN}")
fi

api_curl() {
    curl -fsS "${curl_auth[@]}" "$@"
}

canfar_ps_field() {
    local match_key="$1" match_val="$2" want_field="$3"
    canfar ps -a --json 2>/dev/null | python3 -c "
import json, sys
match_key, match_val, want_field = sys.argv[1:4]
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
for marker in ('[', '{'):
    idx = raw.find(marker)
    if idx >= 0:
        raw = raw[idx:]
        break
try:
    rows = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
if isinstance(rows, dict):
    rows = [rows]
for row in rows:
    if row.get(match_key) == match_val:
        val = row.get(want_field, '')
        if val:
            print(val)
        break
" "${match_key}" "${match_val}" "${want_field}" || true
}

cleanup() {
    if [[ -n "${SESSION_ID}" && -z "${RAY_MANAGER_URL:-}" ]]; then
        echo ""
        echo "Deleting manager session ${SESSION_ID}..."
        canfar delete --force "${SESSION_ID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if ! command -v canfar >/dev/null 2>&1; then
    echo "canfar CLI not found." >&2
    exit 1
fi
if ! canfar auth show >/dev/null 2>&1; then
    echo "canfar not authenticated. Run: canfar auth login" >&2
    exit 1
fi

maybe_registry_auth
load_docker_registry_auth || true
if bootstrap_canfar_registry_on_arc; then
    :
elif [[ -z "${CANFAR_REGISTRY__USERNAME:-}" || -z "${CANFAR_REGISTRY__SECRET:-}" ]]; then
    echo "Warning: no Harbor registry credentials — headless worker/preflight may fail." >&2
    echo "Set CANFAR_REGISTRY__* or docker login ${REGISTRY}" >&2
fi

if [[ -z "${MANAGER_URL}" ]]; then
    echo "CANFAR Ray Milestone B test"
    echo "  manager image: ${FULL_IMAGE}"
    echo "  session name:  ${SESSION_NAME}"
    echo ""
    echo "Creating contributed ray-manager session..."
    CREATE_OUT="$(create_manager_session)" || {
        echo "${CREATE_OUT}" >&2
        exit 1
    }
    echo "${CREATE_OUT}"
    SESSION_ID="$(printf '%s\n' "${CREATE_OUT}" | sed -n 's/.*(ID:[[:space:]]*\([^)]*\)).*/\1/p' | awk '{print $1}')"
    [[ -n "${SESSION_ID}" ]] || SESSION_ID="$(canfar_ps_field name "${SESSION_NAME}" id)"
    [[ -n "${SESSION_ID}" ]] || { echo "Could not parse session ID." >&2; exit 1; }

    echo "Waiting for manager session (ID ${SESSION_ID})..."
    deadline=$((SECONDS + TIMEOUT))
    status=""
    while (( SECONDS < deadline )); do
        status="$(canfar_ps_field id "${SESSION_ID}" status)"
        [[ "${status}" == "Running" ]] && break
        [[ "${status}" == "Failed" || "${status}" == "Error" ]] && break
        sleep 10
    done
    if [[ "${status}" != "Running" ]]; then
        echo "Manager session status: ${status:-timeout}" >&2
        canfar logs "${SESSION_ID}" 2>&1 | tail -50 >&2 || true
        exit 1
    fi
    MANAGER_URL="$(canfar_ps_field id "${SESSION_ID}" connectURL)"
    [[ -n "${MANAGER_URL}" ]] || { echo "No connectURL for manager session." >&2; exit 1; }
fi

MANAGER_URL="${MANAGER_URL%/}"
echo "Manager URL: ${MANAGER_URL}"

echo "Waiting for /readyz..."
deadline=$((SECONDS + 600))
while (( SECONDS < deadline )); do
    if api_curl "${MANAGER_URL}/readyz" >/dev/null 2>&1; then
        break
    fi
    sleep 5
done
api_curl "${MANAGER_URL}/readyz" | python3 -m json.tool

echo ""
echo "Checking CANFAR auth status from manager..."
AUTH_JSON="$(api_curl "${MANAGER_URL}/api/v1/auth/status" || true)"
echo "${AUTH_JSON}" | python3 -m json.tool || echo "${AUTH_JSON}"
if ! printf '%s' "${AUTH_JSON}" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('authenticated') else 1)"; then
    echo ""
    echo "Manager is not authenticated to CANFAR." >&2
    echo "Run 'canfar auth login' once from an AstroAI webterm (persists under /arc/home), then retry." >&2
    exit 1
fi

echo ""
echo "Checking Ray manager UI..."
HTML="$(api_curl "${MANAGER_URL}/" 2>/dev/null || true)"
if [[ -z "${HTML}" ]]; then
    echo "  FAIL could not fetch manager HTML" >&2
    FAILURES=$((FAILURES + 1))
else
    for needle in "CANFAR Ray Manager" '/actions/create-cluster' '/actions/preflight' '/actions/clean-orphans'; do
        if grep -q "${needle}" <<< "${HTML}"; then
            echo "  ok  UI contains ${needle}"
        else
            echo "  FAIL UI missing ${needle}" >&2
            FAILURES=$((FAILURES + 1))
        fi
    done
    CODE="$(api_curl -o /dev/null -w '%{http_code}' -X POST "${MANAGER_URL}/actions/reconcile" 2>/dev/null || echo 000)"
    if [[ "${CODE}" == "303" ]]; then
        echo "  ok  reconcile action redirects (303)"
    else
        echo "  FAIL reconcile action HTTP ${CODE} (expected 303)" >&2
        FAILURES=$((FAILURES + 1))
    fi
fi

echo ""
echo "Checking manager worker image tag..."
STATUS_JSON="$(api_curl "${MANAGER_URL}/api/v1/status" || true)"
WORKER_IMG="$(printf '%s' "${STATUS_JSON}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('worker_image',''))" 2>/dev/null || true)"
echo "  worker_image: ${WORKER_IMG}"
if [[ -n "${WORKER_IMG}" && "${WORKER_IMG}" == *":${TAG}" ]]; then
    echo "  ok  worker image uses tag ${TAG}"
else
    echo "  FAIL worker image tag (expected *:${TAG}, got ${WORKER_IMG})" >&2
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "Running network preflight..."
PF_JSON="$(api_curl -X POST "${MANAGER_URL}/api/v1/preflight/run" || true)"
echo "${PF_JSON}" | python3 -m json.tool || echo "${PF_JSON}"
if ! printf '%s' "${PF_JSON}" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('passed') else 1)"; then
    echo "Network preflight failed." >&2
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "Launching two-worker cluster..."
CLUSTER_JSON="$(api_curl -X POST "${MANAGER_URL}/api/v1/cluster/create" \
    -H 'Content-Type: application/json' \
    -d '{"name":"canfar-ray-test","worker_count":2,"cores":1,"ram_gb":4,"min_joined":2,"partial_policy":"accept_partial","require_preflight":true}' || true)"
echo "${CLUSTER_JSON}" | python3 -m json.tool || echo "${CLUSTER_JSON}"
if ! printf '%s' "${CLUSTER_JSON}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d.get('success') and d.get('joined_workers', 0) >= 2 else 1)
"; then
    echo "Two-worker cluster did not reach healthy state." >&2
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "Stopping cluster..."
api_curl -X POST "${MANAGER_URL}/api/v1/cluster/stop" | python3 -m json.tool || true

echo ""
echo "Destroying any remaining workers..."
api_curl -X POST "${MANAGER_URL}/api/v1/workers/destroy-all" | python3 -m json.tool || true

echo ""
if [[ "${FAILURES}" -eq 0 ]]; then
    echo "CANFAR Ray Milestone B test passed."
    exit 0
fi
echo "CANFAR Ray Milestone B test failed." >&2
exit 1
