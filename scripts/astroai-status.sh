#!/bin/bash -e
# Quick session snapshot for fast feedback loops.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
source /opt/astroai/lib/astroai-env-common.sh

echo "AstroAI session status"
echo "======================"
echo "user:  ${USER}  home: ${HOME}"
echo "pwd:   ${PWD}"
echo "scratch: $(if [[ -d /scratch ]]; then echo yes; else echo no; fi)  tmp: ${TMPDIR:-/tmp}"

# Session age (from common-init.sh timestamp)
if [[ -f "${HOME}/.astroai/session-started" ]]; then
    _start_epoch="$(cat "${HOME}/.astroai/session-started" 2>/dev/null || echo 0)"
    _now_epoch="$(date -u +%s)"
    _age_secs=$(( _now_epoch - _start_epoch ))
    if [[ -n "${_start_epoch}" && "${_start_epoch}" -gt 0 && "${_age_secs}" -ge 0 ]]; then
        if [[ "${_age_secs}" -ge 86400 ]]; then
            _age="$(( _age_secs / 86400 ))d $(( (_age_secs % 86400) / 3600 ))h"
        elif [[ "${_age_secs}" -ge 3600 ]]; then
            _age="$(( _age_secs / 3600 ))h $(( (_age_secs % 3600) / 60 ))m"
        else
            _age="$(( _age_secs / 60 ))m"
        fi
        _start_fmt="$(date -d "@${_start_epoch}" '+%H:%M %Z' 2>/dev/null || echo unknown)"
        echo "session: started ${_start_fmt} (${_age} ago)"
    fi
fi

echo "uptime:  $(uptime 2>/dev/null | sed 's/^.*up//' | sed 's/,.*//' | xargs || echo unknown)"

echo "profile: $(if [[ -n "${ASTROAI_PROFILE_LOADED:-}" ]]; then echo sourced; else echo not sourced; fi)"

if [[ -d /cvmfs/soft.computecanada.ca ]]; then
    echo "cvmfs:   available (source /cvmfs/soft.computecanada.ca/config/profile/bash.sh)"
else
    echo "cvmfs:   not mounted (may be lazy — access a known path first)"
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L &>/dev/null; then
    echo "gpu:   $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
else
    echo "gpu:   not visible (CPU node or no driver)"
fi

kind="$(astroai_detect_project)"
[[ -n "${kind}" ]] && echo "project: ${kind} ($(basename "${PWD}"))" || echo "project: none (cd /scratch && pixi init)"

if command -v uv >/dev/null 2>&1; then
    uv_py_dir="$(uv python dir 2>/dev/null || true)"
    if [[ -n "${uv_py_dir}" ]]; then
        if [[ "${uv_py_dir}" == /usr/local/* ]]; then
            echo "uv:    python dir ${uv_py_dir} (root-only — run: source /etc/profile.d/astroai.sh)"
        else
            echo "uv:    python dir ${uv_py_dir}"
        fi
    fi
fi

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "git:   $(git branch --show-current 2>/dev/null) $(git status -sb 2>/dev/null | head -1)"
fi

echo ""
echo "cadc:"
for tool in canfar cadcget cadc-tap vcp; do
    if command -v "${tool}" >/dev/null 2>&1; then
        ver="$("${tool}" --version 2>&1 | head -1 || true)"
        [[ -z "${ver}" ]] && ver="ok"
        printf "  %-10s %s\n" "${tool}" "${ver}"
    else
        printf "  %-10s %s\n" "${tool}" "NOT FOUND"
    fi
done

echo ""
echo "processes (top by CPU):"
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -6 | sed 's/^/  /'

echo ""
echo "disk:"
# Quota-aware lines for scratch and home
astroai_quota_line /scratch scratch
astroai_quota_line "${HOME}" "home"
_proj="$(astroai_find_arc_project_root)"
[[ -n "${_proj}" ]] && astroai_quota_line "${_proj}" "project"

echo ""
echo "commands: astroai-help | astroai-home-usage | astroai-env-list"
