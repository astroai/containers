#!/bin/bash -e
# AstroAI diagnostic report — session status, tools, disk, network, processes.
#
# Usage:
#   astroai-debug              print to stdout + save to ~/.astroai/debug-<timestamp>.log
#   astroai-debug --stdout     print to stdout only
#   astroai-debug --file path  save to custom path (and print to stdout)

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

SAVE=1
SAVE_PATH=""

usage() {
    cat <<'EOF' >&2
astroai-debug — session diagnostic report.
Usage: astroai-debug [--stdout] [--file <path>]
  --help for details
EOF
    exit 1
}

help_full() {
    cat <<'EOF'
astroai-debug — session diagnostic report.

Collects GPU, disk, tools, network, environment, and process info.
Saves to ~/.astroai/debug-<timestamp>.log by default.

Usage:
  astroai-debug [--stdout] [--file <path>]

Options:
  --stdout          Print to stdout only (do not save to file).
  --file <path>     Save to a custom path (and print to stdout).
  -h                Show short usage summary.
  --help            Show this detailed help.

Examples:
  astroai-debug                             # default: stdout + log file
  astroai-debug --stdout                    # terminal only, no file
  astroai-debug --file /tmp/diag.log        # custom output path

Sections collected:
  Session, Profile, GPU, Disk, Tools, Project, Network, Environment,
  Processes, CVMFS.

Notes:
  • Default log: ~/.astroai/debug-<timestamp>.log
  • Share the log file for remote troubleshooting.
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stdout) SAVE=0; shift ;;
        --file) [[ -n "${2:-}" ]] || { echo "--file requires a path" >&2; exit 1; }; SAVE_PATH="$2"; shift 2 ;;
        -h) usage ;;
        --help) help_full ;;
        *) astroai_err "Unknown option: $1"; usage ;;
    esac
done

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
if [[ "${SAVE}" -eq 1 && -z "${SAVE_PATH}" ]]; then
    mkdir -p "${HOME}/.astroai"
    SAVE_PATH="${HOME}/.astroai/debug-${TIMESTAMP}.log"
fi

if [[ -n "${SAVE_PATH}" ]]; then
    export ASTROAI_UI_PLAIN=1
    exec > >(tee -a "${SAVE_PATH}") 2>&1
fi

section() { astroai_section "$1"; }

astroai_title "AstroAI diagnostic report"
astroai_divider
echo "generated: ${TIMESTAMP}  user: ${USER}  host: $(hostname 2>/dev/null || echo unknown)"

section "Session"
echo "home:     ${HOME}"
echo "src:      ${TMP_SRC_DIR:-not set}"
echo "scratch:  ${TMP_SCRATCH_DIR:-not set} ($(if astroai_scratch_available 2>/dev/null; then echo "writable ($(df -h "$(astroai_scratch_dir)" 2>/dev/null | awk 'NR>1{print $4}' || echo ?))"; else echo "unavailable"; fi))"
echo "pwd:      ${PWD}"
echo "tmp:      ${TMPDIR:-/tmp}"
echo "shell:    ${SHELL:-unknown}  pid: $$"
echo "uptime:   $(uptime 2>/dev/null | sed 's/^.*up//' | sed 's/,.*//' | xargs || echo unknown)"

section "Profile"
if [[ -n "${ASTROAI_PROFILE_LOADED:-}" ]]; then
    echo "ASTROAI_PROFILE_LOADED=1  (profile sourced)"
else
    echo "ASTROAI_PROFILE_LOADED not set — profile may not be sourced"
fi
echo "PATH:     $(echo "${PATH}" | tr ':' '\n' | head -5 | sed 's/^/  /')"
echo "uv dir:   ${UV_PYTHON_INSTALL_DIR:-not set}"
echo "pixi:     ${PIXI_HOME:-not set}"
echo "mamba:    ${MAMBA_ROOT_PREFIX:-not set}"
echo "caches:   UV=${UV_CACHE_DIR:-?}  PIP=${PIP_CACHE_DIR:-?}  NPM=${NPM_CONFIG_CACHE:-?}  PIXI=${PIXI_CACHE_DIR:-?}  CONDA=${MAMBA_PKGS_DIRS:-?}"
echo "ml:       XDG_CACHE=${XDG_CACHE_HOME:-not set}  TORCH=${TORCH_HOME:-not set}  HF=${HF_HOME:-not set}"

section "GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used,memory.free,temperature.gpu,utilization.gpu --format=csv,noheader 2>/dev/null || echo "nvidia-smi query failed"
    echo ""
    echo "GPU processes:"
    nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null || echo "  (none or query failed)"
else
    echo "  nvidia-smi not found — CPU node"
fi

section "Disk"
_src="${TMP_SRC_DIR:-$(astroai_src_dir 2>/dev/null || echo /srcdir)}"
_scr="${TMP_SCRATCH_DIR:-$(astroai_scratch_dir 2>/dev/null || echo /scratch)}"
echo "TMP_SRC_DIR (${_src}):"
if [[ -d "${_src}" ]]; then
    df -h "${_src}" 2>/dev/null | tail -1
else
    echo "  not available"
fi
echo "TMP_SCRATCH_DIR (${_scr}):"
if [[ -d "${_scr}" ]]; then
    df -h "${_scr}" 2>/dev/null | tail -1
else
    echo "  not mounted"
fi
echo "HOME (${HOME}):"
df -h "${HOME}" 2>/dev/null | tail -1
echo ""
echo "Top 10 directories in HOME:"
du -sh "${HOME}"/*/ 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || echo "  (none or no access)"
echo ""
echo "Top 10 under TMP_SRC_DIR:"
if [[ -d "${_src}" ]]; then
    du -sh "${_src}"/*/ 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || echo "  (empty)"
else
    echo "  not available"
fi
echo ""
echo "Top 10 under TMP_SCRATCH_DIR:"
if [[ -d "${_scr}" ]]; then
    du -sh "${_scr}"/*/ 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || echo "  (empty)"
else
    echo "  not mounted"
fi

section "Tools"
for tool in git gh uv pixi python3 nvidia-smi nvtop htop jq rg fd bat fzf delta tldr curl wget rsync zstd patch make lsof xxd hexdump ss host ncdu shellcheck ctags canfar cadcget cadc-tap vcp cadc-get-cert; do
    if command -v "${tool}" >/dev/null 2>&1; then
        ver="$(timeout 2 "${tool}" --version 2>&1 | head -1)"
        printf "  %-12s %s\n" "${tool}" "${ver}"
    else
        printf "  %-12s %s\n" "${tool}" "NOT FOUND"
    fi
done

section "Project"
KIND="$(astroai_detect_project)"
if [[ -n "${KIND}" ]]; then
    echo "type:     ${KIND}"
    echo "dir:      $(basename "${PWD}")"
    if [[ "${KIND}" == "pixi" && -f pixi.lock ]]; then
        echo "lockfile: $(wc -l < pixi.lock) lines"
    elif [[ "${KIND}" == "uv" && -f uv.lock ]]; then
        echo "lockfile: $(wc -l < uv.lock) lines"
    fi
    if [[ -d .pixi ]]; then
        echo "env size: $(du -sh .pixi 2>/dev/null | awk '{print $1}')"
    elif [[ -d .venv ]]; then
        echo "env size: $(du -sh .venv 2>/dev/null | awk '{print $1}')"
    fi
else
    echo "  No pixi or uv project detected in ${PWD}"
    echo "  Hint: cd \"\${TMP_SRC_DIR:-/srcdir}\" && astroai-new myproject"
fi

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree &>/dev/null; then
    echo ""
    echo "git:"
    echo "  branch:  $(git branch --show-current 2>/dev/null || echo unknown)"
    echo "  remote:  $(git remote get-url origin 2>/dev/null || echo none)"
    echo "  status:  $(git status -sb 2>/dev/null | head -1)"
    echo "  last commit: $(git log -1 --format='%h %s (%ar)' 2>/dev/null || echo unknown)"
fi

section "Network"
for endpoint in "pypi.org" "github.com" "conda.anaconda.org" "files.pythonhosted.org"; do
    if curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "https://${endpoint}/" 2>/dev/null | grep -qE '^(2|3)'; then
        echo "  ${endpoint}: reachable"
    else
        echo "  ${endpoint}: UNREACHABLE"
    fi
done

section "Environment" 
echo "Key environment variables (sanitized):"
env | sort | grep -vE '^(TOKEN|SECRET|PASSWORD|KEY|CREDENTIAL|AUTH|GITHUB_TOKEN|AWS_SECRET_ACCESS_KEY|WANDB_API_KEY|HUGGING_FACE_TOKEN|HF_TOKEN|CURSOR_|ANTHROPIC_|OPENAI_|GEMINI_|CODECX_|CLAUDE_)' | grep -iE '^(PATH|HOME|USER|SHELL|LANG|XDG_|UV_|PIXI_|PIP_|HF_|TORCH_|NPM_|MPL_|MAMBA_|CONDA_|TMPDIR|TMP_SRC_DIR|TMP_SCRATCH_DIR|ASTROAI_|JUPYTER_|TERM|LC_|CUDA_|NVIDIA_)' | sed 's/^/  /'

section "Processes"
echo "Top 10 by CPU:"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -11 | sed 's/^/  /'

section "CVMFS"
if [[ -d /cvmfs/soft.computecanada.ca ]]; then
    echo "  /cvmfs/soft.computecanada.ca: accessible"
    echo "  Hint: source /cvmfs/soft.computecanada.ca/config/profile/bash.sh && module avail"
else
    echo "  /cvmfs/soft.computecanada.ca: not accessible (may mount lazily)"
    echo "  Hint: ls /cvmfs/soft.computecanada.ca/config/profile/bash.sh"
fi

echo ""
echo "=================================================="
if [[ -n "${SAVE_PATH}" ]]; then
    echo "Report saved: ${SAVE_PATH}"
    echo "Share with: cat ${SAVE_PATH}"
fi
