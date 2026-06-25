#!/bin/bash -e
# Post-deploy smoke checks for AstroAI images (run inside a CANFAR session).
#
# Usage:
#   canfar-verify.sh              full check (login + non-login shells)
#   canfar-verify.sh --quick        PATH + CADC CLIs only

QUICK=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) QUICK=1; shift ;;
        -h|--help)
            sed -n '2,6p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

failures=0
login_shell() {
    bash -lc "$@"
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

echo "AstroAI image verification"
echo "=========================="

check "astroai-profile on PATH" bash -lc '[[ ":${PATH}:" == *":/opt/astroai/venv/cadc/bin:"* ]]'
check "login shell: canfar" login_shell 'command -v canfar >/dev/null'
check "login shell: cadcget" login_shell 'command -v cadcget >/dev/null'
check "login shell: cadc-tap" login_shell 'command -v cadc-tap >/dev/null'
check "login shell: vcp" login_shell 'command -v vcp >/dev/null'
check "login shell: astroai-help" login_shell 'command -v astroai-help >/dev/null'

for tool in gh rg fd bat fzf uv pixi patch make file xxd hexdump lsof ss host ncdu shellcheck ctags; do
    check "login shell: ${tool}" login_shell "command -v ${tool} >/dev/null"
done

if [[ "${QUICK}" -eq 0 ]]; then
    check "interactive shell: canfar" bash -ic 'command -v canfar >/dev/null' </dev/null
    check "canfar CLI" login_shell 'canfar --help >/dev/null 2>&1'
    check "cadcget --help" login_shell 'cadcget --help >/dev/null 2>&1'
    check "cadcget --version (no SyntaxWarning)" login_shell 'out=$(cadcget --version 2>&1); ! grep -q SyntaxWarning <<<"$out"'
    check "rg search" login_shell 'rg --version >/dev/null 2>&1'
    check "file magic" login_shell 'file /bin/bash | grep -q ELF'
    if login_shell 'command -v node >/dev/null'; then
        check "node --version" login_shell 'node --version >/dev/null 2>&1'
        check "npm --version" login_shell 'npm --version >/dev/null 2>&1'
    fi
fi

echo ""
if [[ "${failures}" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "${failures} check(s) failed." >&2
exit 1
