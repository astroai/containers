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
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — prune soon (astroai-cache-prune --all-safe)"
        return 1
    elif [[ "${used_pct}" -ge 80 ]]; then
        astroai_warn "  ⚠  ${label}: ${used_pct}% used — monitor (astroai-home-usage)"
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
