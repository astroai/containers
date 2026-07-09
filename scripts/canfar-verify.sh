#!/bin/bash -e
set -o pipefail
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

echo "AstroAI image verification"
echo "=========================="

check "astroai-profile on PATH" bash -lc '[[ ":${PATH}:" == *":/opt/astroai/venv/cadc/bin:"* ]]'
check "login shell: canfar" login_shell 'command -v canfar >/dev/null'
check "login shell: cadcget" login_shell 'command -v cadcget >/dev/null'
check "login shell: cadcput" login_shell 'command -v cadcput >/dev/null'
check "login shell: cadc-tap" login_shell 'command -v cadc-tap >/dev/null'
check "login shell: vcp" login_shell 'command -v vcp >/dev/null'
check "login shell: cadc-get-cert" login_shell 'command -v cadc-get-cert >/dev/null'
check "login shell: canfar-lab" login_shell 'command -v canfar-lab >/dev/null'
check "canfar-lab doctor" login_shell 'canfar-lab doctor >/dev/null 2>&1'
check "canfar-lab paths" login_shell 'canfar-lab paths --json | grep -q work_dir'
check "canfar-lab tools" login_shell 'canfar-lab tools --json | grep -q '"'"'"name": "git"'"'"''
check "canfar-lab check" login_shell 'canfar-lab check --json | grep -q '"'"'"ok": true'"'"''
check "CADC venv writable" test -w /opt/astroai/venv/cadc
check "upgrade-cadc-tools helper" test -x /opt/astroai/bin/upgrade-cadc-tools.sh
check "peek helper" test -x /opt/astroai/bin/peek
check "peek on PATH" login_shell 'command -v peek >/dev/null'
check "CANFAR_LAB_BIN_DIR set" login_shell '[[ -n "${CANFAR_LAB_BIN_DIR:-}" ]]'
check "canfar-lab agent bundle" login_shell 'canfar-lab agent install --list >/dev/null'

for tool in gh rg fd bat fzf hyperfine uv pixi micromamba mamba patch make file xxd hexdump lsof ss host ncdu shellcheck ctags \
    gcc g++ gfortran ld ar rustc cargo \
    cmake ninja autoconf automake libtoolize flex bison; do
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
    if login_shell '[[ -n "${TMP_SRC_DIR:-}" && -d "${TMP_SRC_DIR}" && -w "${TMP_SRC_DIR}" ]]'; then
        check "TMP_SRC_DIR writable" login_shell 'test -w "${TMP_SRC_DIR}"'
    fi
    if login_shell '[[ -d "${TMP_SCRATCH_DIR}" && -w "${TMP_SCRATCH_DIR}" ]]'; then
        check "session cache root layout" login_shell \
            'u="${USER:-$(id -un)}"; root="${TMP_SCRATCH_DIR}/.cache-${u}"; [[ "${UV_CACHE_DIR}" == "${root}/"* ]]'
        for var in PIP_CACHE_DIR NPM_CONFIG_CACHE PIXI_CACHE_DIR MAMBA_PKGS_DIRS CONDA_PKGS_DIRS; do
            check "${var} under session cache root" login_shell \
                "u=\"\${USER:-\$(id -un)}\"; root=\"\${TMP_SCRATCH_DIR}/.cache-\${u}\"; [[ \"\${${var}}\" == \"\${root}\"/* ]]"
        done
        check "CANFAR_LAB_BIN_DIR on scratch" login_shell '[[ "${CANFAR_LAB_BIN_DIR}" == "${TMP_SCRATCH_DIR}"/* ]]'
        check "CANFAR_LAB_RUNTIME_ROOT on scratch" login_shell \
            '[[ "${CANFAR_LAB_RUNTIME_ROOT}" == "${TMP_SCRATCH_DIR}"/* ]]'
        check "UV_PYTHON_INSTALL_DIR off home" login_shell '[[ "${UV_PYTHON_INSTALL_DIR}" != "${HOME}"/* ]]'
        check "PIXI_HOME off home when scratch mounted" login_shell '[[ "${PIXI_HOME}" != "${HOME}/.pixi" ]]'
        check "canfar-lab env export" login_shell 'canfar-lab env export --no-ensure | grep -q CANFAR_LAB_BIN_DIR'
    elif login_shell '[[ -n "${TMP_SRC_DIR:-}" ]]'; then
        for var in UV_CACHE_DIR PIP_CACHE_DIR NPM_CONFIG_CACHE PIXI_CACHE_DIR MAMBA_PKGS_DIRS CONDA_PKGS_DIRS; do
            check "${var} under TMP_SRC_DIR" login_shell "[[ \"\${${var}}\" == \"\${TMP_SRC_DIR}\"/* ]]"
        done
    fi

    echo ""
    echo "Running agent setup & install verification..."
    /opt/astroai/bin/canfar-verify-agents.sh || failures=$((failures + 1))
fi

echo ""
if [[ "${failures}" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "${failures} check(s) failed." >&2
exit 1
