# Skaha reverse-proxy path helpers (sourced, not executed).

# Echo base URL path for Jupyter / marimo (no trailing slash), or empty if local.
astroai_skaha_base_url() {
    local session_id="${1:-}"
    local mode="${2:-contrib}"

    [[ -n "${session_id}" ]] || return 0

    case "${mode}" in
        notebook) echo "/session/notebook/${session_id}" ;;
        contrib)  echo "/session/contrib/${session_id}" ;;
        *)        echo "/session/contrib/${session_id}" ;;
    esac
}
