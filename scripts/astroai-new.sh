#!/bin/bash -e
# Start a new project on /scratch with smart defaults.
#
# Usage:
#   astroai-new [name]            pixi init + git init + offer GH repo
#   astroai-new [name] --uv        uv init instead of pixi
#   astroai-new [name] --no-git    skip git init
#   astroai-new [name] --no-gh     skip GitHub repo creation
#   astroai-new [name] --astro     suggest common astro packages

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

NAME=""
USE_UV=0
NO_GIT=0
NO_GH=0
SUGGEST_ASTRO=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uv)      USE_UV=1; shift ;;
        --no-git)  NO_GIT=1; shift ;;
        --no-gh)   NO_GH=1; shift ;;
        --astro)   SUGGEST_ASTRO=1; shift ;;
        -h|--help)
            echo "Usage: astroai-new [name] [flags]"
            echo "  --uv        use uv instead of pixi"
            echo "  --no-git    skip git init"
            echo "  --no-gh     skip GitHub repo creation"
            echo "  --astro     suggest common astro packages"
            exit 0
            ;;
        -*)
            astroai_err "Unknown option: $1"
            astroai_hint "Usage: astroai-new [name] [--uv] [--no-git] [--no-gh] [--astro]"
            exit 1
            ;;
        *)
            if [[ -z "${NAME}" ]]; then
                NAME="$1"
            else
                astroai_err "Unexpected extra argument: $1"
                astroai_hint "Usage: astroai-new [name] [--uv] [--no-git] [--no-gh] [--astro]"
                exit 1
            fi
            shift
            ;;
    esac
done

NAME="${NAME:-project}"

if [[ -d /scratch && -w /scratch ]]; then
    TARGET="/scratch/${NAME}"
else
    TARGET="${HOME}/${NAME}"
fi

if [[ -d "${TARGET}" ]]; then
    if [[ -f "${TARGET}/pixi.toml" || -f "${TARGET}/pyproject.toml" ]]; then
        astroai_err "Project already exists: ${TARGET}"
        astroai_cmd "  cd ${TARGET} && pixi run python script.py"
        exit 1
    fi
    if [[ -n "$(ls -A "${TARGET}" 2>/dev/null)" ]]; then
        astroai_err "Directory exists and is not empty: ${TARGET}"
        astroai_hint "Remove contents or pick a different name."
        exit 1
    fi
fi

# ── Create project directory ─────────────────────
mkdir -p "${TARGET}"
cd "${TARGET}"

echo ""
astroai_info "Creating project: ${NAME}"
astroai_kv "Location:" "${TARGET}"
echo ""

# ── Initialize package manager ───────────────────
if [[ "${USE_UV}" -eq 1 ]]; then
    astroai_hint "  uv init --no-readme"
    uv init --no-readme
    PM="uv"
else
    astroai_hint "  pixi init --no-progress"
    pixi init --no-progress
    PM="pixi"
fi

# ── Git init ─────────────────────────────────────
if [[ "${NO_GIT}" -eq 0 ]]; then
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        astroai_hint "  git init"
        git init -q
        astroai_hint "  git add -A && git commit -m 'Initial commit'"
        git add -A
        git commit -m "Initial commit" --quiet
    fi
fi

# ── GitHub repo (optional) ───────────────────────
if [[ "${NO_GIT}" -eq 0 && "${NO_GH}" -eq 0 ]]; then
    if command -v gh >/dev/null 2>&1 && gh auth status &>/dev/null; then
        echo ""
        if [[ -t 0 ]]; then
            read -r -p "  Create GitHub repo '${NAME}' (private)? [Y/n] " CREATE_GH || true
            CREATE_GH="${CREATE_GH:-y}"
            if [[ "${CREATE_GH}" =~ ^[Yy]$ ]]; then
                gh repo create "${NAME}" --private --source=. --push --remote=origin
                astroai_ok "  ✓ GitHub repo: github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "created")"
            else
                astroai_hint "  Skipped. Create later: gh repo create ${NAME} --private --source=. --push"
            fi
        fi
    else
        astroai_hint "  (run 'gh auth login' to enable GitHub repo creation)"
    fi
fi

# ── Package suggestions ──────────────────────────
if [[ "${SUGGEST_ASTRO}" -eq 1 ]]; then
    echo ""
    astroai_heading "Suggested astro packages:"
    if [[ "${PM}" == "pixi" ]]; then
        astroai_cmd "    pixi add python numpy astropy matplotlib scipy"
        astroai_cmd "    pixi add torch cuda-version=12   # if using GPU"
    else
        astroai_cmd "    uv add numpy astropy matplotlib scipy"
        astroai_cmd "    uv add torch   # if using GPU"
    fi
fi

echo ""
astroai_divider
astroai_ok "  ✓  Project ready: ${NAME}"
astroai_divider
echo ""
astroai_cmd "  cd ${TARGET}"
if [[ "${PM}" == "pixi" ]]; then
    astroai_cmd "  pixi add python numpy"
    astroai_cmd "  pixi run python -c 'print(\"hello\")'"
else
    astroai_cmd "  uv add numpy"
    astroai_cmd "  uv run python -c 'print(\"hello\")'"
fi
echo ""
astroai_warn "  Remember: /scratch is ephemeral — git push your work."
astroai_hint "  Close sessions with: astroai-session-archive"
echo ""
