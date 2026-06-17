# AstroAI shell defaults: PATH, caches, temps, aliases.
# Caches live under ~/.cache on /arc (persistent, easy to prune).
# TMPDIR uses /scratch when mounted (fast, ephemeral).

export PATH="${HOME}/.local/bin:/opt/astroai/bin:${PATH}"

# XDG base dirs (on /arc/home/$USER)
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

# Python package managers
export UV_CACHE_DIR="${UV_CACHE_DIR:-${XDG_CACHE_HOME}/uv}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${XDG_CACHE_HOME}/pip}"
export PIP_DISABLE_PIP_VERSION_CHECK=1

# pixi per-user — override image-level PIXI_HOME=/usr/local/share/pixi
export PIXI_HOME="${HOME}/.pixi"
export PIXI_CACHE_DIR="${HOME}/.pixi/cache"

# ML / data caches (keep out of $HOME root — these grow fast)
export HF_HOME="${HF_HOME:-${XDG_CACHE_HOME}/huggingface}"
export TRANSFORMERS_CACHE="${TRANSFORMERS_CACHE:-${HF_HOME}}"
export HF_DATASETS_CACHE="${HF_DATASETS_CACHE:-${HF_HOME}/datasets}"
export TORCH_HOME="${TORCH_HOME:-${XDG_CACHE_HOME}/torch}"

# Optional tooling caches
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-${XDG_CACHE_HOME}/npm}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-${XDG_CACHE_HOME}/matplotlib}"

# Lightweight env save manifests (lockfiles); see astroai-env-save / astroai-env-resume
export ASTROAI_SAVE_DIR="${ASTROAI_SAVE_DIR:-${HOME}/.astroai/saves}"

# Compile/download temps on scratch SSD when available
if [[ -d /scratch && -w /scratch ]]; then
    export TMPDIR="${TMPDIR:-/scratch/.tmp-${USER:-$(id -un)}}"
fi

alias py="python3"
alias ll="ls -alF"
alias la="ls -A"

if [[ -n "${BASH_VERSION:-}" ]]; then
    command -v uv >/dev/null 2>&1 && eval "$(uv generate-shell-completion bash)"
    command -v pixi >/dev/null 2>&1 && eval "$(pixi completion --shell bash)"
fi
