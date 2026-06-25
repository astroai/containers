#!/bin/bash -e
# JupyterLab for CANFAR Notebook sessions (port 8888).
#
# NOTE: Stock science-platform launch-notebook.yaml runs /skaha-system/start-jupyterlab.sh
# instead of this script. This file is used only when the cluster overrides command to
# /skaha/startup.sh (see docs/OPERATORS.md).
#
# Skaha passes the session ID as the first argument to /skaha/startup.sh.
# The platform also sets JUPYTER_TOKEN to the same value.

source /cadc/common-init.sh

SESSION_ID="${1:-${JUPYTER_TOKEN:-}}"
PORT=8888

# Image config only — ignore deprecated NotebookApp keys in persisted ~/.jupyter.
export JUPYTER_CONFIG_DIR=/etc/jupyter
export JUPYTER_CONFIG_PATH=/etc/jupyter
export JUPYTER_RUNTIME_DIR="${TMPDIR:-/tmp}/jupyter-runtime"
export JUPYTER_DATA_DIR="${TMPDIR:-/tmp}/jupyter-data"
mkdir -p "${JUPYTER_RUNTIME_DIR}" "${JUPYTER_DATA_DIR}"

# notebook_shim still reads legacy NotebookApp keys from persisted ~/.jupyter on /arc/home.
if [[ -d "${HOME}/.jupyter" ]]; then
    _legacy_dir="${HOME}/.jupyter.astroai-legacy"
    shopt -s nullglob
    for _cfg in "${HOME}/.jupyter"/jupyter_{notebook,server,lab}_config.{py,json}; do
        if [[ -f "${_cfg}" ]] && grep -qE 'NotebookApp|c\.NotebookApp' "${_cfg}" 2>/dev/null; then
            mkdir -p "${_legacy_dir}"
            mv "${_cfg}" "${_legacy_dir}/$(basename "${_cfg}").$(date +%s)"
        fi
    done
fi

if [[ -n "${SESSION_ID}" ]]; then
    export JUPYTER_TOKEN="${SESSION_ID}"
fi

BASE_URL_ARGS=()
if [[ -n "${SESSION_ID}" ]]; then
    # Match platform start-jupyterlab.sh (no leading slash)
    BASE_URL_ARGS=(--ServerApp.base_url="session/notebook/${SESSION_ID}")
fi

ROOT_DIR="/scratch"
if [[ ! -d "${ROOT_DIR}" ]]; then
    ROOT_DIR="${HOME}"
fi

exec jupyter lab \
    --ip 0.0.0.0 \
    --port "${PORT}" \
    --no-browser \
    --config /etc/jupyter/jupyter_server_config.py \
    --ServerApp.log_level=ERROR \
    --ServerApp.root_dir="${ROOT_DIR}" \
    "${BASE_URL_ARGS[@]}"
