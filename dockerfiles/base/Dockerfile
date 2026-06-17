# syntax=docker/dockerfile:1
# AstroAI base: platform CLI + monitoring + compression. No browser UI.
#
# Apt packages: only what needs root and is not practical via pixi/uv.
# Compilers, headers, and ML stacks belong in the user's pixi project.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG PYTHON_VERSION=3.13

FROM ${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}

LABEL org.opencontainers.image.title="AstroAI Base" \
      org.opencontainers.image.description="Headless dev environment for CANFAR" \
      io.canfar.skaha.session.type="headless"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    acl \
    bash-completion \
    bzip2 \
    ca-certificates \
    curl \
    file \
    git \
    git-lfs \
    htop \
    jq \
    less \
    locales \
    nvtop \
    openssh-client \
    pigz \
    procps \
    rsync \
    unzip \
    vim-tiny \
    wget \
    xz-utils \
    zip \
    zstd \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8 UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && git lfs install --system

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color

RUN printf '%s\n' \
    '[ -f /etc/profile.d/astroai.sh ] && . /etc/profile.d/astroai.sh' \
    >> /etc/bash.bashrc

COPY scripts/astroai-profile.sh /etc/profile.d/astroai.sh
RUN chmod a+r /etc/profile.d/astroai.sh

RUN mkdir -p /opt/astroai/{bin,cache,lib} /cadc \
    && chmod -R a+rwx /opt/astroai

COPY scripts/lib/astroai-env-common.sh scripts/lib/skaha-proxy.sh /opt/astroai/lib/
COPY scripts/astroai-env-save scripts/astroai-env-resume scripts/astroai-env-list \
    scripts/astroai-home-usage scripts/astroai-cache-prune \
    scripts/astroai-help.sh scripts/astroai-status.sh scripts/astroai-new.sh \
    /opt/astroai/bin/
RUN chmod a+rx /opt/astroai/bin/* /opt/astroai/lib/* \
    && ln -sf astroai-help.sh /opt/astroai/bin/astroai-help \
    && ln -sf astroai-status.sh /opt/astroai/bin/astroai-status \
    && ln -sf astroai-new.sh /opt/astroai/bin/astroai-new

COPY docs/RUNTIME.md /opt/astroai/RUNTIME.md
