#!/bin/bash
# Bootstrap AstroAI shared shell libraries (image or git checkout).

astroai_source_common() {
    local script="${1:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}"
    local dir candidate

    [[ -n "${ASTROAI_ENV_COMMON_LOADED:-}" ]] && return 0

    for dir in /opt/astroai/lib \
        "$(cd "$(dirname "${script}")" && pwd)/lib" \
        "$(cd "$(dirname "${script}")/.." && pwd)/lib"; do
        candidate="${dir}/astroai-env-common.sh"
        if [[ -f "${candidate}" ]]; then
            # shellcheck disable=SC1090
            source "${candidate}"
            return 0
        fi
    done

    return 1
}
