# syntax=docker/dockerfile:1
# AstroAI vscode: OpenVSCode Server in the browser.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
ARG OPENVSCODE_VERSION=v1.109.5

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

ARG OPENVSCODE_VERSION=v1.109.5

LABEL io.canfar.skaha.session.type="contributed"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV SHELL=/bin/bash

RUN ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/') \
    && curl -fsSL \
    "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-${OPENVSCODE_VERSION}/openvscode-server-${OPENVSCODE_VERSION}-linux-${ARCH}.tar.gz" \
    | tar -xz -C /opt \
    && mv "/opt/openvscode-server-${OPENVSCODE_VERSION}-linux-${ARCH}" /opt/openvscode-server

RUN mkdir -p /opt/openvscode-server/data/Machine \
    && printf '%s\n' \
    '{' \
    '  "terminal.integrated.defaultProfile.linux": "bash",' \
    '  "terminal.integrated.profiles.linux": {' \
    '    "bash": { "path": "/bin/bash", "args": ["-l"] }' \
    '  }' \
    '}' \
    > /opt/openvscode-server/data/Machine/settings.json

COPY scripts/common-init.sh scripts/startup-vscode.sh /cadc/
COPY scripts/skaha-startup-vscode.sh /skaha/startup.sh
RUN chmod a+rx /cadc/*.sh /skaha/startup.sh

EXPOSE 5000
WORKDIR /tmp
CMD ["/cadc/startup-vscode.sh"]
