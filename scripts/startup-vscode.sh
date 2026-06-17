#!/bin/bash -e
# OpenVSCode Server on port 5000.

source /cadc/common-init.sh
/opt/astroai/bin/astroai-install-ai.sh

OPS=(
    --host 0.0.0.0
    --port 5000
    --without-connection-token
    --default-folder "${PWD}"
)

if [[ -n "${skaha_sessionid:-}" ]]; then
    OPS+=(--server-base-path "/session/contrib/${skaha_sessionid}")
fi

exec /opt/openvscode-server/bin/openvscode-server "${OPS[@]}"
