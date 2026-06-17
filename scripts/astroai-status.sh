#!/bin/bash -e
# Quick session snapshot for fast feedback loops.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

echo "AstroAI session status"
echo "======================"
echo "user:  ${USER}  home: ${HOME}"
echo "pwd:   ${PWD}"
echo "scratch: $(if [[ -d /scratch ]]; then echo yes; else echo no; fi)  tmp: ${TMPDIR:-/tmp}"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L &>/dev/null; then
    echo "gpu:   $(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
else
    echo "gpu:   not visible (CPU node or no driver)"
fi

kind=""
[[ -f pixi.toml ]] && kind="pixi"
[[ -f pyproject.toml && -z "${kind}" ]] && kind="uv"
[[ -n "${kind}" ]] && echo "project: ${kind} ($(basename "${PWD}"))" || echo "project: none (cd /scratch && pixi init)"

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "git:   $(git branch --show-current 2>/dev/null) $(git status -sb 2>/dev/null | head -1)"
fi

echo ""
echo "disk:"
df -h /scratch "${HOME}" 2>/dev/null | awk 'NR==1 || /scratch|home|\/arc/' || df -h "${HOME}" 2>/dev/null | tail -1

echo ""
echo "commands: astroai-help | astroai-home-usage | astroai-env-list"
