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

  Storage: /srcdir (code)  /scratch (session-private data)  /arc (shared across sessions)
  Backup:  hourly → ~/.astroai/lab/backups/<session>  (astroai-lab backup status)
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
  # Scratch-safe default kernel — notebook sessions only (slow pip install).
  if [[ "${ASTROAI_SESSION_KIND:-}" == "notebook" || "${ASTROAI_LAB_ENSURE_KERNEL:-}" == "1" ]]; then
    astroai-lab kernel ensure --name astroai >/dev/null 2>&1 || true
  fi
  # Agent configs (MCP, rules, skills). UI sessions default to background setup;
  # webterm stays opt-in so terminal users are not surprised.
  #   ASTROAI_LAB_AGENT_SETUP=0     skip (explicit)
  #   ASTROAI_LAB_AGENT_SETUP=1     run in foreground before UI
  #   ASTROAI_LAB_AGENT_SETUP=bg    run in background
  _agent_setup="${ASTROAI_LAB_AGENT_SETUP:-}"
  if [[ -z "${_agent_setup}" ]]; then
    case "${ASTROAI_SESSION_KIND:-}" in
      # marimo runs its own `agent setup marimo` in startup — avoid lock race.
      openresearch|openworker|vscode) _agent_setup=bg ;;
      *) _agent_setup=0 ;;
    esac
  fi
  _agent_state="${HOME}/.astroai/lab"
  _agent_log="${_agent_state}/agent-setup.log"
  _agent_needs_run=0
  if [[ ! -f "${_agent_state}/agent-setup-stamp" || -f "${_agent_state}/agent-setup-failed" ]]; then
    _agent_needs_run=1
  fi
  _run_agent_setup() {
    mkdir -p "${_agent_state}"
    touch "${_agent_state}/agent-setup-pending"
    {
      echo "---- $(date -u +%Y-%m-%dT%H:%M:%SZ) agent setup start kind=${ASTROAI_SESSION_KIND:-} ----"
      astroai-lab --yes agent setup
      _rc=$?
      echo "---- $(date -u +%Y-%m-%dT%H:%M:%SZ) agent setup end exit=${_rc} ----"
      rm -f "${_agent_state}/agent-setup-pending"
      return "${_rc}"
    } >>"${_agent_log}" 2>&1 || true
    rm -f "${_agent_state}/agent-setup-pending"
  }
  case "${_agent_setup}" in
    1|true|yes)
      if [[ "${_agent_needs_run}" == "1" ]]; then
        _run_agent_setup || true
      fi
      ;;
    bg|background)
      if [[ "${_agent_needs_run}" == "1" ]]; then
        (_run_agent_setup || true) &
      fi
      ;;
  esac
  # Hourly /srcdir → /arc/home backup (opt-out: ASTROAI_LAB_BACKUP_ENABLED=false).
  astroai-lab backup start >/dev/null 2>&1 || true
fi

unset ASTROAI_LAB_PROFILE_LOADED
