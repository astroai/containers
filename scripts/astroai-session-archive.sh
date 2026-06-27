#!/bin/bash -e
# Archive current work before closing a session: git push + env save + summary.
#
# Usage:
#   astroai-session-archive         auto-detect project, push + save
#   astroai-session-archive --name  custom save name (default: dir name)
#   astroai-session-archive --force non-interactive (skip prompts)

for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done
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
    astroai_title "Session archive"
    astroai_divider
    echo ""
fi

PUSHED=0
SAVED=0
UNCOMMITTED=0

# ── Git ──────────────────────────────────────────
if git rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH="$(git branch --show-current 2>/dev/null || echo unknown)"
    REMOTE="$(git remote get-url origin 2>/dev/null || echo none)"

    # Check for unstaged / uncommitted changes (skip empty repos with no commits)
    if git rev-parse --verify HEAD >/dev/null 2>&1 \
        && ! git diff-index --quiet HEAD -- 2>/dev/null; then
        UNCOMMITTED=1
        if [[ "${FORCE}" -eq 0 ]]; then
            astroai_warn "⚠  Uncommitted changes detected. Commit before pushing:"
            astroai_cmd "   git add -A && git commit -m 'session work'"
            echo ""
        fi
    fi

    if [[ "${FORCE}" -eq 0 ]]; then
        astroai_info "Pushing branch '${BRANCH}' to ${REMOTE}..."
    fi
    if git push; then
        [[ "${FORCE}" -eq 0 ]] && astroai_ok "✓ pushed ${BRANCH}"
        PUSHED=1
    else
        [[ "${FORCE}" -eq 0 ]] && astroai_err "✗ git push failed — check remote or run: gh auth login"
    fi
else
    [[ "${FORCE}" -eq 0 ]] && astroai_hint "Not in a git repo — skipping push."
    [[ "${FORCE}" -eq 0 ]] && astroai_cmd "  Hint: cd /scratch/myproject && gh repo create myproject --private --source=. --push"
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
        astroai_info "Saving ${KIND} environment '${NAME}'..."
    fi
    if /opt/astroai/bin/astroai-env-save "${NAME}"; then
        [[ "${FORCE}" -eq 0 ]] && astroai_ok "✓ env saved: ${NAME}"
        SAVED=1
    else
        [[ "${FORCE}" -eq 0 ]] && astroai_err "✗ env save failed — run: astroai-env-save ${NAME}"
    fi
else
    [[ "${FORCE}" -eq 0 ]] && astroai_hint "No pixi or uv project detected — skipping env save."
    [[ "${FORCE}" -eq 0 ]] && astroai_cmd "  Hint: pixi init && pixi add python numpy"
fi

if [[ "${FORCE}" -eq 0 ]]; then
    echo ""
    astroai_heading "── Summary ──"
    astroai_kv "  git push:" "$([[ "${PUSHED}" -eq 1 ]] && echo "done" || echo "skipped")"
    astroai_kv "  env save:" "$([[ "${SAVED}" -eq 1 ]] && echo "done (${NAME})" || echo "skipped")"
    if [[ "${UNCOMMITTED}" -eq 1 ]]; then
        astroai_warn "  ⚠  uncommitted changes exist — not archived"
    fi
fi

if [[ -d /scratch ]]; then
    if [[ "${FORCE}" -eq 0 ]]; then
        echo ""
    fi
    if [[ "${PUSHED}" -eq 1 && "${SAVED}" -eq 1 ]]; then
        :  # all good, silent in force mode
    elif [[ "${PUSHED}" -eq 1 ]]; then
        [[ "${FORCE}" -eq 0 ]] && astroai_warn "⚠  /scratch is ephemeral — environment not saved."
    elif [[ "${SAVED}" -eq 1 ]]; then
        [[ "${FORCE}" -eq 0 ]] && astroai_warn "⚠  /scratch is ephemeral — code not pushed."
    else
        [[ "${FORCE}" -eq 0 ]] && astroai_err "⚠  /scratch is ephemeral — nothing archived! Push and save before closing."
    fi
fi
