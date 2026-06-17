#!/bin/bash -e
# JupyterLab for CANFAR Notebook sessions (port 8888).
#
# Skaha passes the session ID as the first argument to /skaha/startup.sh.
# The platform also sets JUPYTER_TOKEN to the same value.

source /cadc/common-init.sh

SESSION_ID="${1:-${JUPYTER_TOKEN:-}}"
PORT=8888

BASE_URL=""
if [[ -n "${SESSION_ID}" ]]; then
    # Match platform start-jupyterlab.sh (no leading slash)
    BASE_URL="--ServerApp.base_url=session/notebook/${SESSION_ID}"
fi

exec jupyter lab \
    --ip 0.0.0.0 \
    --port "${PORT}" \
    --no-browser \
    --ServerApp.token='' \
    --ServerApp.password='' \
    --ServerApp.root_dir="${PWD}" \
    ${BASE_URL}
