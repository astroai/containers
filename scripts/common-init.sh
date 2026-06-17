#!/bin/bash -e
# Shared session setup: workspace on /scratch, cache dirs on /arc.

if [[ -f /etc/profile.d/astroai.sh ]]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/astroai.sh
fi

_cache_dirs=(
    "${HOME}/.local/bin"
    "${HOME}/.astroai/saves"
    "${HOME}/.ssh"
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

if [[ -d /scratch ]]; then
    git config --global --add safe.directory /scratch 2>/dev/null || true
    git config --global --add safe.directory '*' 2>/dev/null || true
    cd /scratch
else
    cd "${HOME}"
fi

if [[ ! -f "${HOME}/.astroai/welcomed" ]]; then
    mkdir -p "${HOME}/.astroai"
    touch "${HOME}/.astroai/welcomed"
    if [[ -t 1 ]] && command -v astroai-help >/dev/null 2>&1; then
        echo ""
        astroai-help | sed -n '1,14p'
        echo "  (full list: astroai-help)"
        echo ""
    fi
fi
