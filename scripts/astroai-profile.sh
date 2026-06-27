# AstroAI shell defaults: PATH, caches, temps, aliases.
# Caches live under ~/.cache on /arc (persistent, easy to prune).
# TMPDIR uses /scratch when mounted (fast, ephemeral).
#
# Bash-only (/etc/profile sources profile.d for all login shells, including sh).
if [ -z "${BASH_VERSION:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

[[ -f /opt/astroai/lib/astroai-env-common.sh ]] && source /opt/astroai/lib/astroai-env-common.sh

# Always ensure platform paths — login children may inherit ASTROAI_PROFILE_LOADED
# from a parent startup shell and hit the guard before PATH is customized.
case ":${PATH}:" in
    *":/opt/astroai/venv/cadc/bin:"*) ;;
    *) export PATH="${HOME}/.local/bin:/opt/astroai/venv/cadc/bin:/opt/astroai/bin:${PATH}" ;;
esac

if [[ -n "${ASTROAI_PROFILE_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
# Shell-local only — do not export; exported guard breaks login shells (bash -l) that
# inherit it from startup scripts while /etc/profile resets PATH first.
ASTROAI_PROFILE_LOADED=1

# XDG base dirs (on /arc/home/$USER)
# Skaha notebook jobs may set XDG_CACHE_HOME=$HOME; keep caches under ~/.cache instead.
if [[ -z "${XDG_CACHE_HOME:-}" || "${XDG_CACHE_HOME}" == "${HOME}" ]]; then
    export XDG_CACHE_HOME="${HOME}/.cache"
fi
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

# Python package managers
export UV_CACHE_DIR="${UV_CACHE_DIR:-${XDG_CACHE_HOME}/uv}"
# Unconditional overrides — image ENV points at /usr/local (root-only); ${VAR:-} would not replace it.
export UV_PYTHON_INSTALL_DIR="${XDG_DATA_HOME}/uv/python"
export UV_PYTHON_BIN_DIR="${HOME}/.local/bin"
export UV_TOOL_DIR="${XDG_DATA_HOME}/uv/tools"
export UV_TOOL_BIN_DIR="${HOME}/.local/bin"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${XDG_CACHE_HOME}/pip}"
export PIP_DISABLE_PIP_VERSION_CHECK=1

# pixi per-user — override image-level PIXI_HOME=/usr/local/share/pixi
export PIXI_HOME="${HOME}/.pixi"
export PIXI_CACHE_DIR="${HOME}/.pixi/cache"

# ML / data caches (keep out of $HOME root — these grow fast)
export HF_HOME="${HF_HOME:-${XDG_CACHE_HOME}/huggingface}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-${HF_HOME}}"
export HF_DATASETS_CACHE="${HF_DATASETS_CACHE:-${HF_HOME}/datasets}"
export TORCH_HOME="${TORCH_HOME:-${XDG_CACHE_HOME}/torch}"

# Optional tooling caches
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${XDG_CACHE_HOME}/npm}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-${XDG_CACHE_HOME}/matplotlib}"

# Lightweight env save manifests (lockfiles); see astroai-env-save / astroai-env-resume
export ASTROAI_SAVE_DIR="${ASTROAI_SAVE_DIR:-${HOME}/.astroai/saves}"

# Compile/download temps on scratch SSD when available
if [[ -d /scratch && -w /scratch ]]; then
    export TMPDIR="${TMPDIR:-/scratch/.tmp-${USER:-$(id -un)}}"
    mkdir -p "${TMPDIR}" 2>/dev/null || true
fi

# /scratch (project envs) and ~/.cache (uv/pixi cache on /arc) are different mounts
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

alias py="python3"
alias ll="ls -alF"
alias la="ls -A"

if [[ -n "${BASH_VERSION:-}" ]]; then
    command -v uv >/dev/null 2>&1 && eval "$(uv generate-shell-completion bash)"
    command -v pixi >/dev/null 2>&1 && eval "$(pixi completion --shell bash)"
    command -v gh >/dev/null 2>&1 && eval "$(gh completion -s bash)"
    command -v rg >/dev/null 2>&1 && eval "$(rg --generate complete-bash)"
    command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"
fi

# ── Periodic /scratch reminder (every ~2 hours of session time) ──
__astroai_scratch_reminder() {
    local _start_file="${HOME}/.astroai/session-started"
    local _reminder_file="${HOME}/.astroai/last-reminder"
    local _interval=7200  # 2 hours

    [[ -t 1 ]] || return 0
    [[ -f "${_start_file}" ]] || return 0

    local _start _now _elapsed _last _since_last
    _start="$(cat "${_start_file}" 2>/dev/null)" || return 0
    [[ -n "${_start}" && "${_start}" -gt 0 ]] || return 0

    printf -v _now '%(%s)T' -1
    _elapsed=$(( _now - _start ))
    (( _elapsed >= _interval )) || return 0

    _last=0
    [[ -f "${_reminder_file}" ]] && _last="$(cat "${_reminder_file}" 2>/dev/null)" || true
    _since_last=$(( _now - _last ))
    (( _since_last >= _interval )) || return 0

    local _hours=$(( _elapsed / 3600 )) _mins=$(( (_elapsed % 3600) / 60 ))

    # Session summary: scratch disk + git commits (only when reminder fires)
    local _summary="" _part

    if [[ -d /scratch ]]; then
        _part="$(df -h /scratch 2>/dev/null | awk 'NR>1 {print $3}')"
        [[ -n "${_part}" ]] && _summary="${_summary}scratch: ${_part}"
    fi

    if git rev-parse --is-inside-work-tree &>/dev/null; then
        _part="$(git rev-list --count HEAD --since="@${_start}" 2>/dev/null)"
        if [[ -n "${_part}" && "${_part}" -gt 0 ]]; then
            [[ -n "${_summary}" ]] && _summary="${_summary} | "
            _summary="${_summary}commits: ${_part}"
        fi
    fi

    if [[ -n "${_summary}" ]]; then
        printf '\n  \033[1;33m⏳ %dh %dm on /scratch (%s)\033[0m\n  → git push or astroai-session-archive\n\n' "${_hours}" "${_mins}" "${_summary}"
    else
        printf '\n  \033[1;33m⏳ %dh %dm on /scratch — git push or astroai-session-archive\033[0m\n\n' "${_hours}" "${_mins}"
    fi

    mkdir -p "${HOME}/.astroai"
    printf '%s' "${_now}" > "${_reminder_file}"
}

# ── Periodic quota reminder (every ~6 hours, only when home >80%) ──
__astroai_quota_reminder() {
    local _reminder_file="${HOME}/.astroai/last-quota-reminder"
    local _interval=21600  # 6 hours

    [[ -t 1 ]] || return 0
    [[ -d "${HOME}" ]] || return 0

    local _now _last _since_last
    printf -v _now '%(%s)T' -1
    _last=0
    [[ -f "${_reminder_file}" ]] && _last="$(cat "${_reminder_file}" 2>/dev/null)" || true
    _since_last=$(( _now - _last ))
    (( _since_last >= _interval )) || return 0

    local _used_pct
    _used_pct="$(astroai_quota_used_pct "${HOME}")"
    [[ -n "${_used_pct}" ]] || return 0

    # Always record that we checked, so df doesn't run on every prompt
    mkdir -p "${HOME}/.astroai"
    printf '%s' "${_now}" > "${_reminder_file}"

    (( _used_pct >= 80 )) || return 0

    local _level _color
    if (( _used_pct >= 95 )); then
        _level="CRITICAL"
        _color='\033[1;31m'  # red
    elif (( _used_pct >= 90 )); then
        _level="high"
        _color='\033[1;33m'  # yellow
    else
        _level="monitor"
        _color='\033[1;33m'  # yellow
    fi
    printf '\n  %b⚠  home: %d%% used (%s) — astroai-cache-prune --all-safe%b\n\n' "${_color}" "${_used_pct}" "${_level}" '\033[0m'
}

# ── Pre-exit auto-archive (once per git repo per session) ──
__astroai_auto_archive() {
    local _root _hash _marker _log

    git rev-parse --is-inside-work-tree &>/dev/null || return 0
    _root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
    _hash="$(printf '%s' "${_root}" | sha256sum | awk '{print $1}')"
    _marker="${HOME}/.astroai/auto-archived-${_hash}"
    _log="${HOME}/.astroai/auto-archive.log"

    [[ -f "${_marker}" ]] && return 0

    mkdir -p "${HOME}/.astroai"
    touch "${_marker}"
    if astroai-session-archive --force >>"${_log}" 2>&1; then
        return 0
    fi
    rm -f "${_marker}"
}

__astroai_on_exit() {
    __astroai_auto_archive
    if [[ -n "${__ASTROAI_PRIOR_EXIT_TRAP:-}" ]]; then
        eval "${__ASTROAI_PRIOR_EXIT_TRAP}"
    fi
}

if [[ -t 1 ]]; then
    __ASTROAI_PRIOR_EXIT_TRAP="$(
        trap -p EXIT 2>/dev/null | sed -n "s/^trap -- '\(.*\)' EXIT\$/\1/p" || true
    )"
    if [[ -z "${__ASTROAI_PRIOR_EXIT_TRAP}" || "${__ASTROAI_PRIOR_EXIT_TRAP}" == "__astroai_on_exit" ]]; then
        unset __ASTROAI_PRIOR_EXIT_TRAP
    fi
    trap __astroai_on_exit EXIT
fi

if [[ -t 1 ]]; then
    if [[ -z "${PROMPT_COMMAND:-}" ]]; then
        PROMPT_COMMAND="__astroai_scratch_reminder; __astroai_quota_reminder"
    else
        PROMPT_COMMAND="${PROMPT_COMMAND}; __astroai_scratch_reminder; __astroai_quota_reminder"
    fi
fi
