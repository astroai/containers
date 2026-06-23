#!/bin/bash -e
# Archive current work before closing a session: git push + env save + summary.
#
# Usage:
#   astroai-session-archive         auto-detect project, push + save
#   astroai-session-archive --name  custom save name (default: dir name)
#   astroai-session-archive --force non-interactive (skip prompts)

source /opt/astroai/lib/astroai-env-common.sh
[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

NAME=""
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            [[ -n "${2:-}" ]] || { echo "--name requires a value" >&2; exit 1; }
            NAME="$2"
            shift 2
            ;;
        --force|-f) FORCE=1; shift ;;
        -h|--help)
            sed -n '2,7p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ "${FORCE}" -eq 0 ]]; then
    echo "Session archive"
    echo "==============="
    echo ""
fi

PUSHED=0
SAVED=0
UNCOMMITTED=0

# ── Git ──────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH="$(git branch --show-current 2>/dev/null || echo unknown)"
    REMOTE="$(git remote get-url origin 2>/dev/null || echo none)"

    # Check for unstaged / uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        UNCOMMITTED=1
        if [[ "${FORCE}" -eq 0 ]]; then
            echo "⚠  Uncommitted changes detected. Commit before pushing:"
            echo "   git add -A && git commit -m 'session work'"
            echo ""
        fi
    fi

    if [[ "${FORCE}" -eq 0 ]]; then
        echo "Pushing branch '${BRANCH}' to ${REMOTE}..."
    fi
    if git push; then
        [[ "${FORCE}" -eq 0 ]] && echo "✓ pushed ${BRANCH}"
        PUSHED=1
    else
        [[ "${FORCE}" -eq 0 ]] && echo "✗ git push failed — check remote or run: gh auth login"
    fi
else
    [[ "${FORCE}" -eq 0 ]] && echo "Not in a git repo — skipping push."
    [[ "${FORCE}" -eq 0 ]] && echo "  Hint: cd /scratch/myproject && gh repo create myproject --private --source=. --push"
fi

if [[ "${FORCE}" -eq 0 ]]; then
    echo ""
fi

# ── Environment ──────────────────────────────────
KIND="$(astroai_detect_project)"
if [[ -n "${KIND}" ]]; then
    if [[ -z "${NAME}" ]]; then
        NAME="$(basename "${PWD}")"
    fi

    if [[ "${FORCE}" -eq 0 ]]; then
        echo "Saving ${KIND} environment '${NAME}'..."
    fi
    if /opt/astroai/bin/astroai-env-save "${NAME}"; then
        [[ "${FORCE}" -eq 0 ]] && echo "✓ env saved: ${NAME}"
        SAVED=1
    else
        [[ "${FORCE}" -eq 0 ]] && echo "✗ env save failed — run: astroai-env-save ${NAME}"
    fi
else
    [[ "${FORCE}" -eq 0 ]] && echo "No pixi or uv project detected — skipping env save."
    [[ "${FORCE}" -eq 0 ]] && echo "  Hint: pixi init && pixi add python numpy"
fi

if [[ "${FORCE}" -eq 0 ]]; then
    echo ""
    echo "── Summary ──"
    echo "  git push:   $([[ "${PUSHED}" -eq 1 ]] && echo "done" || echo "skipped")"
    echo "  env save:   $([[ "${SAVED}" -eq 1 ]] && echo "done (${NAME})" || echo "skipped")"
    if [[ "${UNCOMMITTED}" -eq 1 ]]; then
        echo "  ⚠  uncommitted changes exist — not archived"
    fi
fi

if [[ -d /scratch ]]; then
    if [[ "${FORCE}" -eq 0 ]]; then
        echo ""
    fi
    if [[ "${PUSHED}" -eq 1 && "${SAVED}" -eq 1 ]]; then
        :  # all good, silent in force mode
    elif [[ "${PUSHED}" -eq 1 ]]; then
        [[ "${FORCE}" -eq 0 ]] && echo "⚠  /scratch is ephemeral — environment not saved."
    elif [[ "${SAVED}" -eq 1 ]]; then
        [[ "${FORCE}" -eq 0 ]] && echo "⚠  /scratch is ephemeral — code not pushed."
    else
        [[ "${FORCE}" -eq 0 ]] && echo "⚠  /scratch is ephemeral — nothing archived! Push and save before closing."
    fi
fi
