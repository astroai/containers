#!/bin/bash -e
# Clone a GitHub repo under TMP_SRC_DIR and install its dependencies.
#
# Usage:
#   astroai-clone owner/repo
#   astroai-clone owner/repo "${TMP_SRC_DIR}/custom-dir"

for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

usage() {
    cat <<'EOF' >&2
astroai-clone — clone a GitHub repo and install deps.
Usage: astroai-clone <owner/repo> [target-dir]
  --help for details
EOF
}

help_full() {
    cat <<'EOF'
astroai-clone — clone a GitHub repo and install deps.

Usage:
  astroai-clone <owner/repo> [target-dir]

Options:
  -h          Short help (stderr, exit 1)
  --help      This help (stdout, exit 0)

Clones a GitHub repo via `gh repo clone` and runs `pixi install`
or `uv sync` if a pixi.toml or pyproject.toml is found.

Defaults to TMP_SRC_DIR/<repo-name> when target-dir is omitted.
Requires `gh auth login` for GitHub access.

Examples:
  astroai-clone astroai/astroai-containers
  astroai-clone myorg/myproject
  astroai-clone myorg/myproject "${TMP_SRC_DIR}/custom"
EOF
}

case "${1:-}" in
    -h) usage; exit 1 ;;
    --help) help_full; exit 0 ;;
esac

for _arg in "$@"; do
    case "${_arg}" in
        -h) usage; exit 1 ;;
        --help) help_full; exit 0 ;;
    esac
done

REPO="${1:-}"
TARGET="${2:-}"

if [[ -z "${REPO}" ]]; then
    usage
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    astroai_err "gh (GitHub CLI) is required. Run: gh auth login"
    exit 1
fi

REPO_NAME="${REPO##*/}"
SRC_DIR="$(astroai_src_dir)"

if [[ -z "${TARGET}" ]]; then
    TARGET="${SRC_DIR}/${REPO_NAME}"
fi

if [[ -d "${TARGET}" ]]; then
    astroai_err "Target already exists: ${TARGET}"
    exit 1
fi

astroai_info "Cloning ${REPO} -> ${TARGET}..."
gh repo clone "${REPO}" "${TARGET}"

cd "${TARGET}"

KIND="$(astroai_detect_project)"
case "${KIND}" in
    pixi)
        astroai_info "Installing pixi environment..."
        pixi install
        echo ""
        astroai_ok "Ready: cd ${TARGET}"
        astroai_cmd "  pixi run python script.py"
        ;;
    uv)
        astroai_info "Installing uv environment..."
        uv sync
        echo ""
        astroai_ok "Ready: cd ${TARGET}"
        astroai_cmd "  uv run python script.py"
        ;;
    *)
        astroai_hint "No pixi.toml or pyproject.toml found — skipping dependency install."
        astroai_cmd "  pixi init   (or: uv init)"
        astroai_cmd "  pixi add python numpy"
        echo ""
        astroai_ok "Ready: cd ${TARGET}"
        ;;
esac
