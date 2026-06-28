#!/bin/bash -e
# Shared session setup: code on TMP_SRC_DIR, data on TMP_SCRATCH_DIR, config on /arc.

if [[ -f /etc/profile.d/astroai.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/astroai.sh
fi

_cache_dirs=(
    "${CANFAR_LAB_BIN_DIR:-${HOME}/.local/bin}"
    "${CANFAR_LAB_SAVE_DIR:-${HOME}/.canfar/lab/saves}"
    "${CANFAR_LAB_CONFIG_DIR:-${HOME}/.canfar/lab}"
    "${HOME}/.ssh"
    "${XDG_CONFIG_HOME:-${HOME}/.config}"
    "${XDG_CACHE_HOME:-${HOME}/.cache}"
    "${UV_CACHE_DIR:-${HOME}/.cache/uv}"
    "${PIP_CACHE_DIR:-${HOME}/.cache/pip}"
    "${PIXI_HOME:-${HOME}/.pixi}"
    "${PIXI_CACHE_DIR:-${HOME}/.pixi/cache}"
    "${MAMBA_ROOT_PREFIX:-${HOME}/.local/share/micromamba}"
    "${MAMBA_PKGS_DIRS:-${HOME}/.cache/conda/pkgs}"
    "${NPM_CONFIG_CACHE:-${HOME}/.cache/npm}"
    "${HF_HOME:-${HOME}/.cache/huggingface}"
    "${TORCH_HOME:-${HOME}/.cache/torch}"
    "${MPLCONFIGDIR:-${HOME}/.cache/matplotlib}"
)

for d in "${_cache_dirs[@]}"; do
    mkdir -p "${d}"
done
chmod 700 "${HOME}/.ssh" 2>/dev/null || true

if [[ -n "${TMPDIR:-}" ]]; then
    mkdir -p "${TMPDIR}"
fi

# Source lib for quota helper before the quota check
if [[ -f /opt/astroai/lib/astroai-env-common.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/astroai/lib/astroai-env-common.sh
fi

command -v astroai_quota_startup_check &>/dev/null && astroai_quota_startup_check

if astroai_scratch_available; then
    git config --global --add safe.directory "$(astroai_scratch_dir)" 2>/dev/null || true
fi
_src_root="$(astroai_src_dir)"
git config --global --add safe.directory "${_src_root}" 2>/dev/null || true
mkdir -p "${_src_root}"
cd "${_src_root}"

# Track session start time for canfar-lab status; reset per-session auto-archive markers
_state="${CANFAR_LAB_CONFIG_DIR:-${HOME}/.canfar/lab}"
mkdir -p "${_state}"
date -u +%s > "${_state}/session-started"
rm -f "${_state}/auto-archived" "${_state}"/auto-archived-*

if [[ ! -f "${_state}/welcomed" ]]; then
    touch "${_state}/welcomed"
    if [[ -t 1 ]]; then
        cat <<'WELCOME'

  ╔══════════════════════════════════════════════════════╗
  ║       Welcome to CANFAR Lab!                        ║
  ╚══════════════════════════════════════════════════════╝

  Quick start:
    canfar-lab init myproject          create a new project
    canfar-lab clone owner/repo        clone a GitHub project (--from-env for shared deps)

  Once you have code:
    pixi run python analysis.py        run your project
    git push                            back up to GitHub
    canfar-lab push                     save everything before closing

  Storage:
    TMP_SRC_DIR         code + env (see canfar-lab doctor)
    TMP_SCRATCH_DIR     datasets + caches when mounted
    CANFAR_LAB_BIN_DIR  agent CLI installs (scratch when mounted)
    /arc/home           persistent config in ~/.canfar/lab

  Getting help:
    canfar-lab guide                    full command list
    less /opt/astroai/USAGE.md          detailed usage guide

  AI coding agents (once per user, persists on scratch or team project):
    canfar-lab agent setup              MCP + skills — run this first
    canfar-lab agent install agent      or claude, goose, opencode, codex
    canfar-lab agent update             refresh after image upgrade
WELCOME
        if [[ "${ASTROAI_SESSION_KIND:-}" == "webterm" ]]; then
            cat <<'WEBTERM'

  tmux tabs (prefix Ctrl-b):
    c        new window (tab)
    n / p    next / previous window
    0-9      jump to window number
    w        pick from window list
    % / "    split pane vertical / horizontal
WEBTERM
        fi
    fi
fi

# Startup scripts exec(3) into ttyd/jupyter/etc. Drop the profile guard so login
# children (bash -l in webterm tmux) re-source profile after /etc/profile.
unset CANFAR_LAB_PROFILE_LOADED
