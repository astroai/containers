#!/bin/bash -e
# Shared session setup: code on TMP_SRC_DIR, data on TMP_SCRATCH_DIR, config on /arc.

if [[ -f /etc/profile.d/astroai.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/astroai.sh
fi

_cache_dirs=(
    "${ASTROAI_LAB_BIN_DIR:-${HOME}/.local/bin}"
    "${ASTROAI_LAB_SAVE_DIR:-${HOME}/.astroai/lab/saves}"
    "${ASTROAI_LAB_CONFIG_DIR:-${HOME}/.astroai/lab}"
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

# Track session start time for astroai-lab status; reset per-session auto-archive markers
_state="${ASTROAI_LAB_CONFIG_DIR:-${HOME}/.astroai/lab}"
mkdir -p "${_state}"
date -u +%s > "${_state}/session-started"
rm -f "${_state}/auto-archived" "${_state}"/auto-archived-*

if [[ ! -f "${_state}/welcomed" ]]; then
    touch "${_state}/welcomed"
    if [[ -t 1 ]]; then
        cat <<'WELCOME'

  Welcome to AstroAI on CANFAR!
  ─────────────────────────────
  astroai-lab init <name>     New project       astroai-lab guide    Full command list
  astroai-lab clone <repo>    Clone from GitHub  less /opt/astroai/USAGE.md  Full docs

  Storage: TMP_SRC_DIR (code)  /scratch (data)  /arc/home (persistent)
  Agents:  astroai-lab agent install claude|goose|opencode|codex
WELCOME
        if [[ "${ASTROAI_SESSION_KIND:-}" == "webterm" ]]; then
            printf '\n\033[1;36m%s\033[0m\n' "  Tmux: Ctrl-b c (new tab)  Ctrl-b n/p (switch)  Ctrl-b z (zoom)"
        fi
    fi
fi

# Startup scripts exec(3) into ttyd/jupyter/etc. Drop the profile guard so login
# children (bash -l in webterm tmux) re-source profile after /etc/profile.

# Notebook-safe caches even when platform overrides Jupyter CMD.
if command -v astroai-lab >/dev/null 2>&1; then
  # Apply cache redirects for this process tree.
  eval "$(astroai-lab env export 2>/dev/null)" || true
  # Best-effort scratch-safe default kernel (no-op without jupyter/ipykernel).
  astroai-lab kernel ensure --name astroai >/dev/null 2>&1 || true
  # Agent configs (MCP, rules, skills, model presets) — idempotent;
  # persists on /arc/home. First run clones upstream skills (~30s);
  # subsequent sessions are instant. Agent binaries installed on-demand
  # via `astroai-lab agent install <tool>` (lightweight, no image bloat).
  astroai-lab --yes agent setup >/dev/null 2>&1 || true
fi

unset ASTROAI_LAB_PROFILE_LOADED
