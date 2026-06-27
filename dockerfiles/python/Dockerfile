# syntax=docker/dockerfile:1
# AstroAI Python foundation: Debian slim + uv + pixi (system-wide paths).
# uv/pixi: official install scripts (latest at build time), not pinned GHCR tags.

ARG PYTHON_VERSION=3.13
ARG UV_VERSION=0.11.25
ARG PIXI_VERSION=0.71.1

FROM python:${PYTHON_VERSION}-slim

LABEL org.opencontainers.image.title="AstroAI Python Runtime" \
      org.opencontainers.image.vendor="AstroAI"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    UV_TOOL_DIR=/usr/local/share/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    PIXI_HOME=/usr/local/share/pixi \
    PIXI_BIN_DIR=/usr/local/bin \
    PIXI_CACHE_DIR=/usr/local/share/pixi/cache
# ^ build-time paths for `uv pip install --system` only.
# Session users: /etc/profile.d/astroai.sh overrides UV_* and PIXI_HOME to ~/.local and ~/.pixi.

RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh \
    | env UV_VERSION="${UV_VERSION}" UV_UNMANAGED_INSTALL=/usr/local/bin sh \
    && curl -fsSL https://pixi.sh/install.sh \
    | env PIXI_VERSION="${PIXI_VERSION}" PIXI_HOME=/usr/local/share/pixi PIXI_BIN_DIR=/usr/local/bin bash \
    && uv --version \
    && pixi --version \
    && command -v uvx >/dev/null
