# syntax=docker/dockerfile:1
# AstroAI full: base + current Node.js LTS (system-wide node/npm for npm CLIs).

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
ARG NODE_VERSION=v24.18.0
ARG NODE_SHA256_X64=55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742
ARG NODE_SHA256_ARM64=58c9520501f6ae2b52d5b210444e24b9d0c029a58c5011b797bc1fe7105886f6

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

LABEL org.opencontainers.image.title="AstroAI Full" \
      org.opencontainers.image.description="Base + Node.js LTS for npm-based CLIs" \
      io.canfar.skaha.session.type="headless"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN ARCH="$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')" \
    && case "${ARCH}" in \
        x64) SHA256="${NODE_SHA256_X64}" ;; \
        arm64) SHA256="${NODE_SHA256_ARM64}" ;; \
        *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && TARBALL="node-${NODE_VERSION}-linux-${ARCH}.tar.xz" \
    && curl -fsSL -o "${TARBALL}" "https://nodejs.org/dist/${NODE_VERSION}/${TARBALL}" \
    && echo "${SHA256}  ${TARBALL}" | sha256sum -c - \
    && tar -xJ -C /usr/local --strip-components=1 -f "${TARBALL}" \
    && rm "${TARBALL}" \
    && node --version \
    && npm --version
