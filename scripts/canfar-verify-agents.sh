#!/bin/bash -e
set -o pipefail
# Agent setup + install smoke checks (run inside a CANFAR session).
#
# Usage:
#   canfar-verify-agents.sh           full agent setup, models, and install loop
#   canfar-verify-agents.sh --setup   setup + verify + models only (no installs)

SETUP_ONLY=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup-only) SETUP_ONLY=1; shift ;;
        -h|--help)
            sed -n '2,6p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

failures=0
skips=0

login_shell() {
    bash -lc "$*"
}

check() {
    local label="$1"
    shift
    if "$@"; then
        printf '  ok  %s\n' "${label}"
    else
        printf '  FAIL %s\n' "${label}" >&2
        failures=$((failures + 1))
    fi
}

skip() {
    local label="$1"
    local reason="$2"
    printf '  skip %s (%s)\n' "${label}" "${reason}"
    skips=$((skips + 1))
}

gh_authed() {
    login_shell 'gh auth status >/dev/null 2>&1'
}

needs_gh_auth() {
    case "$1" in codex|ast-grep) return 0 ;; *) return 1 ;; esac
}

install_cmd_for() {
    case "$1" in
        ast-grep) echo sg ;;
        *) echo "$1" ;;
    esac
}

install_path_candidates() {
    local tool="$1"
    local cmd path
    cmd="$(install_cmd_for "${tool}")"
    if [[ -n "${CANFAR_LAB_BIN_DIR:-}" ]]; then
        printf '%s\n' "${CANFAR_LAB_BIN_DIR}/${cmd}"
    fi
    printf '%s\n' "${HOME}/.local/bin/${cmd}"
    case "${tool}" in
        opencode) printf '%s\n' "${HOME}/.opencode/bin/opencode" ;;
    esac
}

install_binary_present() {
    local tool="$1"
    local path
    while IFS= read -r path; do
        if login_shell "test -x \"${path}\""; then
            return 0
        fi
    done < <(install_path_candidates "${tool}")
    local cmd
    cmd="$(install_cmd_for "${tool}")"
    login_shell "command -v ${cmd} >/dev/null"
}

check_install() {
    local tool="$1"

    if needs_gh_auth "${tool}" && ! gh_authed; then
        skip "agent install ${tool}" "gh auth login required"
        return 0
    fi

    if ! login_shell "canfar-lab --yes agent install ${tool}"; then
        printf '  FAIL agent install %s (install command)\n' "${tool}" >&2
        failures=$((failures + 1))
        return 0
    fi
    if install_binary_present "${tool}"; then
        printf '  ok  agent install %s\n' "${tool}"
    else
        printf '  FAIL agent install %s (binary not found after install)\n' "${tool}" >&2
        failures=$((failures + 1))
    fi
}

echo "Agent setup & install verification"
echo "=================================="

check "agent setup" login_shell 'canfar-lab --yes agent setup'
check "agent verify" login_shell 'canfar-lab agent verify'
check "agent setup stamp" login_shell 'test -f "${HOME}/.canfar/lab/agent-setup-stamp"'
check "cursor MCP" login_shell 'python3 -c "import json, pathlib; d=json.loads(pathlib.Path(\"${HOME}/.cursor/mcp.json\").read_text()); assert d.get(\"mcpServers\")"'
check "canfar-lab-workflow skill" login_shell 'test -f "${HOME}/.cursor/skills/canfar-lab-workflow/SKILL.md"'
check "kilo starter config" login_shell 'test -f "${HOME}/.config/kilo/kilo.jsonc"'
check "free-models guide" login_shell 'test -f "${HOME}/.config/canfar/lab/free-models-guide.txt"'
check "agent-env hook" login_shell 'test -f "${HOME}/.config/canfar/lab/agent-env.sh"'

check "agent models list" login_shell 'canfar-lab agent models list | grep -q coding'
check "agent models free" login_shell 'canfar-lab --yes agent models free'
check "goose openrouter config" login_shell 'grep -q GOOSE_PROVIDER "${HOME}/.config/goose/config.yaml"'
check "opencode model config" login_shell 'python3 -c "import json, pathlib; d=json.loads(pathlib.Path(\"${HOME}/.config/opencode/opencode.json\").read_text()); assert d.get(\"model\", \"\").startswith(\"openrouter/\")"'
check "openrouter.env.example" login_shell 'test -f "${HOME}/.config/canfar/lab/openrouter.env.example"'

check "agent install --list" login_shell 'canfar-lab agent install --list | grep -q kilo'

if [[ "${SETUP_ONLY}" -eq 1 ]]; then
    echo ""
    if [[ "${failures}" -eq 0 ]]; then
        echo "Agent setup checks passed (${skips} skipped)."
        exit 0
    fi
    echo "${failures} agent setup check(s) failed." >&2
    exit 1
fi

echo ""
echo "Agent tool installs"
echo "-------------------"

# node first — npm-based agents depend on it.
AGENT_TOOLS=(
    node
    goose
    opencode
    swival
    kilo
    cline
    freebuff
    pi
    codewhale
    agent
    claude
    agy
    copilot
    codex
    ast-grep
    hyperfine
)

for tool in "${AGENT_TOOLS[@]}"; do
    check_install "${tool}"
done

echo ""
if [[ "${failures}" -eq 0 ]]; then
    echo "All agent checks passed (${skips} skipped)."
    exit 0
fi
echo "${failures} agent check(s) failed (${skips} skipped)." >&2
exit 1
