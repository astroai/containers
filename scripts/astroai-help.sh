#!/bin/bash -e
# AstroAI user command reference.

for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

usage() {
    cat <<'EOF' >&2
astroai-help — quick command reference (see USAGE.md for details).
Usage: astroai-help
  --help for details
EOF
    exit 1
}

help_full() {
    cat <<'EOF'
astroai-help — quick command reference.

Prints a categorized list of AstroAI commands on stdout.
For full documentation: less /opt/astroai/USAGE.md

Usage:
  astroai-help

Options:
  -h          Short help (stderr, exit 1)
  --help      This help (stdout, exit 0)
EOF
    exit 0
}

case "${1:-}" in
    -h) usage ;;
    --help) help_full ;;
    "")
        ;;
    *)
        astroai_err "Unexpected argument: $1"
        usage
        ;;
esac

astroai_title "AstroAI commands (on PATH via /opt/astroai/bin)"
astroai_divider
echo ""

astroai_heading "Quick loop"
astroai_cmd "  astroai-status              where am I, gpu, git, disk, session age"
astroai_cmd "  astroai-new [name]          pixi init + git + GH repo (--uv, --no-git, --no-gh, --astro)"
astroai_cmd "  astroai-clone owner/repo    clone + install deps (optional target dir)"
echo ""

astroai_heading "Environment save/resume (/arc-friendly)"
astroai_cmd "  astroai-env-save [name]     save lockfiles to ~/.astroai/saves (--full, --to)"
astroai_cmd "  astroai-env-resume <name>   restore env on TMP_SRC_DIR + pixi install (--from, [path])"
astroai_cmd "  astroai-env-list            list personal saves (--team, --all)"
echo ""

astroai_heading "Runtime paths (override at session launch)"
astroai_hint "  TMP_SRC_DIR                 code + env (default: /srcdir, ASTROAI_DEFAULT_SRC_DIR)"
astroai_hint "  TMP_SCRATCH_DIR             datasets + download caches (default: /scratch)"
astroai_cmd "  astroai-workspace-save      freeze code + .pixi/.venv (--with-cache, --to)"
astroai_cmd "  astroai-workspace-restore   offline batch restore — no network (--from, --to)"
echo ""

astroai_heading "JupyterLab (notebook sessions)"
astroai_cmd "  astroai-kernel-register     add cwd pixi/uv/venv to kernel picker (on demand)"
astroai_cmd "  astroai-kernel-register --list | --unregister | --name | <path>"
echo ""

astroai_heading "Home hygiene (shared CephFS)"
astroai_cmd "  astroai-home-usage          disk breakdown under \$HOME"
astroai_cmd "  astroai-cache-prune --all-safe   clear pip/uv/npm/pixi/conda caches"
astroai_cmd "  astroai-cache-prune --hf    also drop Hugging Face model cache"
astroai_cmd "  astroai-debug               diagnostic report (--stdout, --file)"
astroai_cmd "  astroai-debug --stdout      print only (no file save)"
echo ""

astroai_heading "Project workflow"
astroai_cmd "  astroai-project-init <name> create team workspace on /arc/projects (--members)"
astroai_cmd "  pixi install / uv sync      deps into project (not system image)"
astroai_cmd "  astroai-session-archive     git push + env save + summary (--force, --name)"
astroai_cmd "  git push                    before session ends — TMP_SRC_DIR is ephemeral"
echo ""

astroai_heading "Reminders (interactive login shells)"
astroai_hint "  ~every 2h                   yellow TMP_SRC_DIR nudge (git push or archive)"
astroai_hint "  on shell exit               auto astroai-session-archive --force once (in git repo)"
echo ""

astroai_heading "Dev CLIs (pre-installed)"
astroai_cmd "  gh, rg, fd, bat, fzf, delta, tldr   GitHub + fast search/browse"
astroai_cmd "  gh auth login               one-time GitHub token setup"
echo ""

astroai_heading "CADC / CANFAR clients (pre-installed — see USAGE.md)"
astroai_cmd "  cadcget, cadcput, vcp, cadc-tap, canfar, cadc-get-cert"
astroai_cmd "  canfar auth login           Science Platform authentication"
echo ""

astroai_heading "AI agents (install once to ~/.local/bin on /arc — see USAGE.md)"
astroai_cmd "  astroai-install node       Node.js + npm via pixi (persistent on /arc)"
astroai_cmd "  astroai-install <tool>     Cursor Agent (agent), claude, agy, opencode, codex,"
astroai_cmd "                             copilot, goose, pi, codewhale, swival, freebuff"
astroai_cmd "  astroai-install --list     full list + install methods"
astroai_hint "  curl: Cursor Agent (agent), claude, agy, opencode, copilot, goose"
astroai_hint "  gh release (no Node): codex"
astroai_hint "  uv tool (no Node): swival"
astroai_hint "  npm (needs node): pi, codewhale, freebuff"
echo ""

astroai_heading "Docs"
astroai_cmd "  less /opt/astroai/USAGE.md  (or docs/USAGE.md in repo)"
echo ""

astroai_heading "Storage"
astroai_hint "  TMP_SRC_DIR      code + env (default /srcdir — ephemeral)"
astroai_hint "  TMP_SCRATCH_DIR  datasets + uv/pip/npm/pixi/conda caches (default /scratch)"
astroai_hint "  ~/.cache         ML/tool caches on /arc (prune when large)"
astroai_hint "  ~/.astroai       env save manifests"
astroai_cmd "  astroai-data-stage <src> [dst]  copy data to TMP_SCRATCH_DIR for fast I/O"
astroai_cmd "  astroai-data-sync <src> <tgt>   sync TMP_SCRATCH_DIR results to persistent"
