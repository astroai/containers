# syntax=docker/dockerfile:1
# AstroAI vscode: OpenVSCode Server in the browser.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
ARG OPENVSCODE_VERSION=openvscode-server-v1.109.5
ARG OPENVSCODE_SHA256_X64=b433bf4f0227321a7014d8460d10a8f958adc0f45aa79bd889e84e65e8f88363
ARG OPENVSCODE_SHA256_ARM64=36d9c14036489b63de84ebace837fcacf7e60e669a0dc715802c5443684ea4dc

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

LABEL io.canfar.skaha.session.type="contributed"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV SHELL=/bin/bash

RUN ARCH=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/') \
    && case "${ARCH}" in \
        x64) SHA256="${OPENVSCODE_SHA256_X64}" ;; \
        arm64) SHA256="${OPENVSCODE_SHA256_ARM64}" ;; \
        *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && TARBALL="${OPENVSCODE_VERSION}-linux-${ARCH}.tar.gz" \
    && curl -fsSL -o "${TARBALL}" \
        "https://github.com/gitpod-io/openvscode-server/releases/download/${OPENVSCODE_VERSION}/${TARBALL}" \
    && echo "${SHA256}  ${TARBALL}" | sha256sum -c - \
    && tar -xzf "${TARBALL}" -C /opt \
    && mv "/opt/${OPENVSCODE_VERSION}-linux-${ARCH}" /opt/openvscode-server \
    && rm "${TARBALL}" \
    && chmod -R a+rx /opt/openvscode-server

RUN mkdir -p /opt/openvscode-server/data/Machine
COPY config/openvscode-settings.json /opt/openvscode-server/data/Machine/settings.json

COPY scripts/common-init.sh scripts/startup-vscode.sh /cadc/
COPY scripts/skaha-startup-vscode.sh /skaha/startup.sh
RUN chmod a+rx /cadc/*.sh /skaha/startup.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/ >/dev/null

WORKDIR /tmp
CMD ["/skaha/startup.sh"]
