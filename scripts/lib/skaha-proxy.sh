# Skaha reverse-proxy path helpers (sourced, not executed).

# Echo base URL path for Jupyter / marimo (with trailing slash), or empty if local.
astroai_skaha_base_url() {
    local session_id="${1:-}"
    local mode="${2:-contrib}"

    [[ -n "${session_id}" ]] || return 0

    case "${mode}" in
        notebook) echo "/session/notebook/${session_id}/" ;;
        contrib)  echo "/session/contrib/${session_id}/" ;;
        *)        echo "/session/contrib/${session_id}/" ;;
    esac
}

# Resolve session id and mode from Skaha launch (notebook passes $1; contributed sets env).
astroai_skaha_session() {
    if [[ -n "${1:-}" ]]; then
        echo "notebook ${1}"
    elif [[ -n "${skaha_sessionid:-}" ]]; then
        echo "contrib ${skaha_sessionid}"
    fi
}
