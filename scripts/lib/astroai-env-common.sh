# Shared helpers for AstroAI env save/resume wrappers.

astroai_save_root() {
    echo "${ASTROAI_SAVE_DIR:-${HOME}/.astroai/saves}"
}

astroai_ensure_save_root() {
    local root
    root="$(astroai_save_root)"
    mkdir -p "${root}"
}

astroai_detect_project() {
    if [[ -f pixi.toml ]]; then
        echo pixi
    elif [[ -f pyproject.toml && -f uv.lock ]]; then
        echo uv
    elif [[ -f pyproject.toml ]]; then
        echo uv
    else
        echo ""
    fi
}

astroai_require_project() {
    local kind
    kind="$(astroai_detect_project)"
    if [[ -z "${kind}" ]]; then
        echo "No pixi or uv project here (need pixi.toml or pyproject.toml)." >&2
        exit 1
    fi
    echo "${kind}"
}

astroai_timestamp() {
    date -u +%Y%m%dT%H%M%SZ
}
