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
            echo "Unknown option: $1" >&2
            echo "Usage: astroai-new [name] [--uv] [--no-git] [--no-gh] [--astro]" >&2
            exit 1
            ;;
        *)
            if [[ -z "${NAME}" ]]; then
                NAME="$1"
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

if [[ -d "${TARGET}" ]] && [[ -f "${TARGET}/pixi.toml" || -f "${TARGET}/pyproject.toml" ]]; then
    echo "Project already exists: ${TARGET}" >&2
    echo "  cd ${TARGET} && pixi run python script.py" >&2
    exit 1
fi

# ── Create project directory ─────────────────────
mkdir -p "${TARGET}"
cd "${TARGET}"

echo ""
echo "  Creating project: ${NAME}"
echo "  Location: ${TARGET}"
echo ""

# ── Initialize package manager ───────────────────
if [[ "${USE_UV}" -eq 1 ]]; then
    echo "  uv init --no-readme"
    uv init --no-readme
    PM="uv"
else
    echo "  pixi init --no-progress"
    pixi init --no-progress
    PM="pixi"
fi

# ── Git init ─────────────────────────────────────
if [[ "${NO_GIT}" -eq 0 ]]; then
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        echo "  git init"
        git init -q
        echo "  git add -A && git commit -m 'Initial commit'"
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
                echo "  ✓ GitHub repo: github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "created")"
            else
                echo "  Skipped. Create later: gh repo create ${NAME} --private --source=. --push"
            fi
        fi
    else
        echo "  (run 'gh auth login' to enable GitHub repo creation)"
    fi
fi

# ── Package suggestions ──────────────────────────
if [[ "${SUGGEST_ASTRO}" -eq 1 ]]; then
    echo ""
    echo "  Suggested astro packages:"
    if [[ "${PM}" == "pixi" ]]; then
        echo "    pixi add python numpy astropy matplotlib scipy"
        echo "    pixi add torch cuda-version=12   # if using GPU"
    else
        echo "    uv add numpy astropy matplotlib scipy"
        echo "    uv add torch   # if using GPU"
    fi
fi

# ── Summary ──────────────────────────────────────
echo ""
echo "  ════════════════════════════════════════"
echo "  ✓  Project ready: ${NAME}"
echo "  ════════════════════════════════════════"
echo ""
echo "  cd ${TARGET}"
if [[ "${PM}" == "pixi" ]]; then
    echo "  pixi add python numpy"
    echo "  pixi run python -c 'print(\"hello\")'"
else
    echo "  uv add numpy"
    echo "  uv run python -c 'print(\"hello\")'"
fi
echo ""
echo "  Remember: /scratch is ephemeral — git push your work."
echo "  Close sessions with: astroai-session-archive"
echo ""
