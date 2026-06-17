# syntax=docker/dockerfile:1
# AstroAI Python foundation: Debian slim + uv + pixi (system-wide paths).

FROM ghcr.io/prefix-dev/pixi:0.58.0 AS pixi
FROM ghcr.io/astral-sh/uv:0.9.1 AS uv

FROM python:3.13-slim

LABEL org.opencontainers.image.title="AstroAI Python 3.13 Runtime" \
      org.opencontainers.image.vendor="AstroAI"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=pixi /usr/local/bin/pixi /usr/local/bin/pixi
COPY --from=uv /uv /usr/local/bin/uv
COPY --from=uv /uvx /usr/local/bin/uvx

ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin \
    UV_TOOL_DIR=/usr/local/share/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    PIXI_HOME=/usr/local/share/pixi \
    PIXI_BIN_DIR=/usr/local/bin \
    PIXI_CACHE_DIR=/usr/local/share/pixi/cache
