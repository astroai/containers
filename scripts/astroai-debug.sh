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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stdout) SAVE=0; shift ;;
        --file) [[ -n "${2:-}" ]] || { echo "--file requires a path" >&2; exit 1; }; SAVE_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,7p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
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
echo "pwd:      ${PWD}"
echo "scratch:  $(if [[ -d /scratch ]]; then echo "mounted ($(df -h /scratch 2>/dev/null | awk 'NR>1{print $4}' || echo ?))"; else echo "not mounted"; fi)"
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
echo "caches:   XDG_CACHE=${XDG_CACHE_HOME:-not set}  TORCH=${TORCH_HOME:-not set}  HF=${HF_HOME:-not set}"

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
echo "/scratch:"
if [[ -d /scratch ]]; then
    df -h /scratch 2>/dev/null | tail -1
else
    echo "  not mounted"
fi
echo "HOME (${HOME}):"
df -h "${HOME}" 2>/dev/null | tail -1
echo ""
echo "Top 10 directories in HOME:"
du -sh "${HOME}"/*/ 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || echo "  (none or no access)"
echo ""
echo "Scratch usage:"
if [[ -d /scratch ]]; then
    du -sh /scratch/*/ 2>/dev/null | sort -rh | head -10 | sed 's/^/  /' || echo "  (empty)"
else
    echo "  /scratch not mounted"
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
    echo "  Hint: cd /scratch && astroai-new myproject"
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
env | sort | grep -vE '^(TOKEN|SECRET|PASSWORD|KEY|CREDENTIAL|AUTH|GITHUB_TOKEN|AWS_SECRET_ACCESS_KEY|WANDB_API_KEY|HUGGING_FACE_TOKEN|HF_TOKEN|CURSOR_|ANTHROPIC_|OPENAI_|GEMINI_|CODECX_|CLAUDE_)' | grep -iE '^(PATH|HOME|USER|SHELL|LANG|XDG_|UV_|PIXI_|PIP_|HF_|TORCH_|NPM_|MPL_|TMPDIR|ASTROAI_|JUPYTER_|TERM|LC_|CUDA_|NVIDIA_)' | sed 's/^/  /'

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
