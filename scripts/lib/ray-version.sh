#!/usr/bin/bash
# Resolve RAY_VERSION_EXPECTED from env, build stamp, or installed package.
set -euo pipefail

ray_version_expected() {
    if [[ -n "${RAY_VERSION_EXPECTED:-}" ]]; then
        printf '%s\n' "${RAY_VERSION_EXPECTED}"
        return 0
    fi
    if [[ -f /opt/astroai/ray-version.txt ]]; then
        tr -d '[:space:]' </opt/astroai/ray-version.txt
        return 0
    fi
    local py="${RAY_PYTHON:-/opt/astroai/venv/ray/bin/python}"
    "${py}" -c 'import ray; print(ray.__version__)'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ray_version_expected
fi
