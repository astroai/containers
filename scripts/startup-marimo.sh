#!/bin/bash -e
# Marimo reactive notebooks on port 5000.

source /cadc/common-init.sh
# shellcheck disable=SC1091
source /opt/astroai/lib/skaha-proxy.sh

BASE_URL_ARG=()
if [[ -n "${skaha_sessionid:-}" ]]; then
    BASE_URL_ARG=(--base-url "$(astroai_skaha_base_url "${skaha_sessionid}" contrib)")
fi

exec marimo --log-level INFO edit \
    --no-token \
    --port 5000 \
    --host 0.0.0.0 \
    --skip-update-check \
    --headless \
    "${BASE_URL_ARG[@]}"
