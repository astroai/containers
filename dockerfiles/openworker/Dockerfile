# syntax=docker/dockerfile:1
# AstroAI openworker: OpenWorker browser UI + Python server (no Tauri).
# Pin OPENWORKER_SHA; document upstream https://github.com/andrewyng/openworker

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
ARG OPENWORKER_SHA=4766e59c47c0201cbecb22b0e22cc1d0b188446b
ARG NODE_VERSION=20

# --- Build Vite GUI (relative asset URLs; API injected at runtime by proxy) ---
FROM node:${NODE_VERSION}-bookworm-slim AS gui-build
ARG OPENWORKER_SHA
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir repo && cd repo \
    && git init \
    && git remote add origin https://github.com/andrewyng/openworker.git \
    && git fetch --depth 1 origin "${OPENWORKER_SHA}" \
    && git checkout FETCH_HEAD \
    && cd surfaces/gui \
    && npm ci \
    && npm run build

# --- Runtime image ---
FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

ARG OPENWORKER_SHA

LABEL io.canfar.skaha.session.type="contributed" \
      org.opencontainers.image.title="AstroAI OpenWorker" \
      org.opencontainers.image.description="OpenWorker browser UI + local agent server for CANFAR (no Tauri)" \
      org.opencontainers.image.source="https://github.com/andrewyng/openworker" \
      org.opencontainers.image.revision="${OPENWORKER_SHA}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install OpenWorker Python package into an isolated venv (aisuite from git).
RUN mkdir -p /opt/openworker/src \
    && python3 -m venv /opt/openworker/venv \
    && /opt/openworker/venv/bin/pip install -U pip setuptools wheel \
    && cd /opt/openworker/src \
    && git init \
    && git remote add origin https://github.com/andrewyng/openworker.git \
    && git fetch --depth 1 origin "${OPENWORKER_SHA}" \
    && git checkout FETCH_HEAD \
    && /opt/openworker/venv/bin/pip install --no-cache-dir . \
    && /opt/openworker/venv/bin/openworker-server --help >/dev/null \
    && rm -rf /root/.cache/pip

COPY --from=gui-build /src/repo/surfaces/gui/dist /opt/openworker/gui

ENV PATH="/opt/openworker/venv/bin:/opt/astroai/bin:${PATH}" \
    ASTROAI_SESSION_KIND=openworker \
    OPENWORKER_UI_ROOT=/opt/openworker/gui \
    OPENWORKER_PORT=8765 \
    ASTROAI_OPENWORKER_PORT=5000 \
    ASTROAI_AGENT_WIZARD_PORT=4792

COPY scripts/lib/skaha-proxy.sh \
     scripts/lib/agent-wizard.py \
     scripts/lib/openworker-canfar-proxy.py \
     /opt/astroai/lib/
COPY scripts/common-init.sh scripts/startup-openworker.sh /cadc/
COPY scripts/skaha-startup-openworker.sh /skaha/startup.sh
RUN chmod a+rx /opt/astroai/lib/openworker-canfar-proxy.py \
        /opt/astroai/lib/agent-wizard.py \
        /cadc/*.sh /skaha/startup.sh \
    && chmod a+r /opt/astroai/lib/skaha-proxy.sh \
    && test -f /opt/openworker/gui/index.html

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/ >/dev/null

WORKDIR /tmp
CMD ["/skaha/startup.sh"]
