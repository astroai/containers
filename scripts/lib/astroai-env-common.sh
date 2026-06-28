# Shared helpers for AstroAI env save/resume wrappers.

ASTROAI_ENV_COMMON_LOADED=1
set -o pipefail 2>/dev/null || true

if [[ -f /opt/astroai/lib/astroai-ui.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/astroai/lib/astroai-ui.sh
elif [[ -f "${BASH_SOURCE[0]%/*}/astroai-ui.sh" ]]; then
    # shellcheck disable=SC1091
    source "${BASH_SOURCE[0]%/*}/astroai-ui.sh"
fi

astroai_save_root() {
    echo "${ASTROAI_SAVE_DIR:-${HOME}/.astroai/saves}"
}

astroai_ensure_save_root() {
    local root
    root="$(astroai_save_root)"
    mkdir -p "${root}"
}

# Resolve a canfar-lab save directory (--from overrides default save root).
astroai_env_save_resolve() {
    local name="$1"
    local from_override="${2:-}"
    local dir

    if [[ -n "${from_override}" ]]; then
        dir="${from_override%/}"
    else
        dir="$(astroai_save_root)/${name}"
    fi

    if [[ ! -f "${dir}/manifest.json" ]]; then
        astroai_err "Save not found: ${dir}"
        astroai_cmd "List saves: canfar-lab saves"
        exit 1
    fi
    echo "${dir}"
}

# Install a saved env in a temp dir to warm uv/pip/pixi download caches (no repo changes).
astroai_env_warm_cache() {
    local save_dir="$1"
    local kind

    kind="$(jq -r .kind "${save_dir}/manifest.json")"

    (
        local tmp
        tmp="$(mktemp -d)"
        trap 'rm -rf "${tmp}"' EXIT

        case "${kind}" in
            pixi)
                [[ -f "${save_dir}/pixi.toml" ]] || exit 0
                cp -a "${save_dir}/pixi.toml" "${tmp}/"
                [[ -f "${save_dir}/pixi.lock" ]] && cp -a "${save_dir}/pixi.lock" "${tmp}/"
                cd "${tmp}" && pixi install --quiet
                ;;
            uv)
                [[ -f "${save_dir}/pyproject.toml" ]] || exit 0
                cp -a "${save_dir}/pyproject.toml" "${tmp}/"
                [[ -f "${save_dir}/uv.lock" ]] && cp -a "${save_dir}/uv.lock" "${tmp}/"
                cd "${tmp}" && uv sync --quiet
                ;;
        esac
    )
}

# Copy a saved lockfile into the current project when upstream omitted one.
# Sets ASTROAI_BOOTSTRAP_LOCK=1 when a lock was copied (caller may need fallback).
astroai_env_bootstrap_lock() {
    local save_dir="$1"
    local project_kind="$2"
    local save_kind

    ASTROAI_BOOTSTRAP_LOCK=0
    save_kind="$(jq -r .kind "${save_dir}/manifest.json")"

    if [[ "${project_kind}" != "${save_kind}" ]]; then
        astroai_hint "Save is ${save_kind}, project is ${project_kind} — cache warmed only."
        return 0
    fi

    case "${project_kind}" in
        pixi)
            [[ -f pixi.toml ]] || return 0
            [[ -f pixi.lock ]] && return 0
            [[ -f "${save_dir}/pixi.lock" ]] || return 0
            cp -a "${save_dir}/pixi.lock" ./pixi.lock
            ASTROAI_BOOTSTRAP_LOCK=1
            astroai_hint "Bootstrap: copied pixi.lock from saved env (session-local)."
            astroai_hint "Publish for OSS: pixi lock && git add pixi.lock && git commit"
            ;;
        uv)
            [[ -f pyproject.toml ]] || return 0
            [[ -f uv.lock ]] && return 0
            [[ -f "${save_dir}/uv.lock" ]] || return 0
            cp -a "${save_dir}/uv.lock" ./uv.lock
            ASTROAI_BOOTSTRAP_LOCK=1
            astroai_hint "Bootstrap: copied uv.lock from saved env (session-local)."
            astroai_hint "Publish for OSS: uv lock && git add uv.lock && git commit"
            ;;
    esac
}

astroai_detect_project() {
    if [[ -f pixi.toml ]]; then
        echo pixi
    elif [[ -f pyproject.toml && -f uv.lock ]]; then
        echo uv
    elif [[ -f pyproject.toml ]]; then
        echo uv
    else
        echo ""
    fi
}

astroai_require_project() {
    local kind
    kind="$(astroai_detect_project)"
    if [[ -z "${kind}" ]]; then
        astroai_err "No pixi or uv project here (need pixi.toml or pyproject.toml)."
        exit 1
    fi
    echo "${kind}"
}

astroai_timestamp() {
    date -u +%Y%m%dT%H%M%SZ
}

# Runtime paths — set TMP_SRC_DIR / TMP_SCRATCH_DIR to override; defaults from image ENV only.
astroai_default_src_dir() {
    echo "${ASTROAI_DEFAULT_SRC_DIR:-/srcdir}"
}

astroai_default_scratch_dir() {
    echo "${ASTROAI_DEFAULT_SCRATCH_DIR:-/scratch}"
}

astroai_scratch_dir() {
    echo "${TMP_SCRATCH_DIR:-$(astroai_default_scratch_dir)}"
}

astroai_scratch_available() {
    local _scratch
    _scratch="$(astroai_scratch_dir)"
    [[ -d "${_scratch}" && -w "${_scratch}" ]]
}

# Code/env root: TMP_SRC_DIR when set, else default src dir if writable, else scratch, else HOME.
astroai_src_dir() {
    if [[ -n "${TMP_SRC_DIR:-}" ]]; then
        echo "${TMP_SRC_DIR}"
        return
    fi
    # Legacy alias (deprecated)
    if [[ -n "${ASTROAI_WORK_ROOT:-}" ]]; then
        echo "${ASTROAI_WORK_ROOT}"
        return
    fi
    local _default_src
    _default_src="$(astroai_default_src_dir)"
    if [[ -d "${_default_src}" && -w "${_default_src}" ]]; then
        echo "${_default_src}"
    elif astroai_scratch_available; then
        echo "$(astroai_scratch_dir)"
    else
        echo "${HOME}"
    fi
}

# Fast SSD workspace snapshots for offline batch (never run software from /arc).
astroai_workspace_root() {
    echo "$(astroai_src_dir)/.astroai/workspaces"
}

astroai_scratch_cache_root() {
    local _user="${USER:-$(id -un)}"
    if astroai_scratch_available; then
        echo "$(astroai_scratch_dir)/.cache-${_user}"
    else
        echo "$(astroai_src_dir)/.cache-${_user}"
    fi
}

astroai_workspace_bundle_dir() {
    local name="$1"
    echo "$(astroai_workspace_root)/${name}"
}

# Echo integer 0-100 used percentage for path, or empty if unknown.
astroai_quota_used_pct() {
    local path="${1:-}"
    [[ -d "${path}" ]] || return 0
    df "${path}" 2>/dev/null | awk 'NR>1 {used=$3; size=$2; if(size>0) printf "%.0f", (used/size)*100; else print 0}'
}

# Echo /arc/projects/<name> when start path is inside a project, else empty.
astroai_find_arc_project_root() {
    local start="${1:-${PWD}}"
    local proj_path="${start}"

    [[ -d /arc/projects ]] || return 0
    while [[ "${proj_path}" != "/" && "${proj_path}" != "/arc/projects" ]]; do
        local parent
        parent="$(dirname "${proj_path}")"
        if [[ "${parent}" == /arc/projects ]]; then
            echo "${proj_path}"
            return 0
        fi
        proj_path="${parent}"
    done
}

# Check storage quota for a path. Prints warnings at thresholds.
# Returns: 0 = OK, 1 = warning (>80%), 2 = critical (>95%)
# Usage: astroai_check_quota "/arc/home/user" ["label"]
astroai_check_quota() {
    local path="${1:-}"
    local label="${2:-$(basename "${path}")}"

    [[ -d "${path}" ]] || return 0

    local used_pct
    used_pct="$(astroai_quota_used_pct "${path}")"
    [[ -n "${used_pct}" ]] || return 0

    if [[ "${used_pct}" -ge 95 ]]; then
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — CRITICAL (near quota limit)"
        return 2
    elif [[ "${used_pct}" -ge 90 ]]; then
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — prune soon (canfar-lab clean home --all-safe)"
        return 1
    elif [[ "${used_pct}" -ge 80 ]]; then
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — monitor (canfar-lab status)"
        return 1
    fi
    return 0
}

# Print a one-line quota summary for a path.
# Usage: astroai_quota_line "/arc/home/user" "home"
astroai_quota_line() {
    local path="${1:-}"
    local label="${2:-$(basename "${path}")}"

    [[ -d "${path}" ]] || { echo "  ${label}: not mounted"; return; }

    df -h "${path}" 2>/dev/null | awk -v lbl="${label}" 'NR>1 {
        pct=$5; gsub(/%/, "", pct);
        if (pct >= 95) alert=" ⚠ CRITICAL";
        else if (pct >= 90) alert=" ⚠ high";
        else if (pct >= 80) alert=" ⚠ monitor";
        else alert="";
        printf "  %-8s %s / %s (%s%%)%s\n", lbl, $3, $2, $5, alert
    }'
}

# Run quota warnings for relevant paths at session start.
# Skip when stderr is not a TTY (CANFAR session logs capture startup stderr).
astroai_quota_startup_check() {
    if [[ ! -t 2 ]]; then
        return 0
    fi

    local warned=0

    # Home quota (always relevant)
    if [[ -d "${HOME}" ]]; then
        astroai_check_quota "${HOME}" "home (/arc/home/${USER})" || warned=1
    fi

    # Project quota (if PWD is inside /arc/projects/<project>)
    local proj_path
    proj_path="$(astroai_find_arc_project_root)"
    if [[ -n "${proj_path}" ]]; then
        local proj_label="project ($(basename "${proj_path}"))"
        astroai_check_quota "${proj_path}" "${proj_label}" || warned=1
    fi

    if [[ "${warned}" -eq 1 ]]; then
        echo ""
    fi
    return 0
}
