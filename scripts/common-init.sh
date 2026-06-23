#!/bin/bash -e
# Shared session setup: workspace on /scratch, cache dirs on /arc.

if [[ -f /etc/profile.d/astroai.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/astroai.sh
fi

_cache_dirs=(
    "${HOME}/.local/bin"
    "${HOME}/.local/share/uv/python"
    "${HOME}/.local/share/uv/tools"
    "${HOME}/.astroai/saves"
    "${HOME}/.ssh"
    "${XDG_CONFIG_HOME:-${HOME}/.config}"
    "${XDG_CACHE_HOME:-${HOME}/.cache}"
    "${UV_CACHE_DIR:-${HOME}/.cache/uv}"
    "${PIP_CACHE_DIR:-${HOME}/.cache/pip}"
    "${PIXI_HOME:-${HOME}/.pixi}"
    "${PIXI_CACHE_DIR:-${HOME}/.pixi/cache}"
    "${HF_HOME:-${HOME}/.cache/huggingface}"
    "${TORCH_HOME:-${HOME}/.cache/torch}"
    "${NPM_CONFIG_CACHE:-${HOME}/.cache/npm}"
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

astroai_quota_startup_check

if [[ -d /scratch ]]; then
    git config --global --add safe.directory /scratch 2>/dev/null || true
    git config --global --add safe.directory '*' 2>/dev/null || true
    cd /scratch
else
    cd "${HOME}"
fi

# Track session start time for astroai-status; reset per-session exit hook marker
mkdir -p "${HOME}/.astroai"
date -u +%s > "${HOME}/.astroai/session-started"
rm -f "${HOME}/.astroai/auto-archived"

if [[ ! -f "${HOME}/.astroai/welcomed" ]]; then
    touch "${HOME}/.astroai/welcomed"
    if [[ -t 1 ]]; then
        cat <<'WELCOME'

  ╔══════════════════════════════════════════════════════╗
  ║       Welcome to AstroAI on CANFAR!                 ║
  ╚══════════════════════════════════════════════════════╝

  Quick start:
    astroai-new myproject          create a new project
    astroai-clone owner/repo       clone a GitHub project

  Once you have code:
    pixi run python analysis.py    run your project
    git push                        back up to GitHub
    astroai-session-archive         save everything before closing

  Storage:
    /scratch        active work (ephemeral — wiped at session end)
    /arc/home       persistent (caches, saves, config, AI tools)

  Getting help:
    astroai-help                    full command list
    less /opt/astroai/USAGE.md      detailed usage guide

WELCOME
    fi
fi
