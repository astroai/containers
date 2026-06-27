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
    bat \
    bind9-dnsutils \
    bsdextrautils \
    bzip2 \
    ca-certificates \
    curl \
    fd-find \
    file \
    fzf \
    gh \
    git \
    git-delta \
    git-lfs \
    htop \
    iproute2 \
    jq \
    less \
    locales \
    lsof \
    make \
    ncdu \
    nvtop \
    openssh-client \
    patch \
    pigz \
    procps \
    ripgrep \
    rsync \
    shellcheck \
    tealdeer \
    tree \
    libmagic1 \
    universal-ctags \
    unzip \
    vim-tiny \
    wget \
    xxd \
    xz-utils \
    zip \
    zstd \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8 UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && git lfs install --system \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && git config --system core.pager delta \
    && git config --system interactive.diffFilter 'delta --color-only' \
    && git config --system delta.navigate true

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color \
    SHELL=/bin/bash

RUN printf '%s\n' \
    '[ -f /etc/profile.d/astroai.sh ] && . /etc/profile.d/astroai.sh' \
    >> /etc/bash.bashrc

COPY scripts/astroai-profile.sh /etc/profile.d/astroai.sh
RUN chmod a+r /etc/profile.d/astroai.sh

RUN mkdir -p /opt/astroai/{bin,cache,lib,venv} /cadc \
    && chmod -R a+rX /opt/astroai \
    && chmod -R a+rwx /opt/astroai/cache

COPY config/cadc-tools.txt /opt/astroai/cadc-tools.txt
COPY scripts/patch-clint-py313.sh /tmp/patch-clint-py313.sh
RUN uv venv /opt/astroai/venv/cadc \
    && uv pip install --python /opt/astroai/venv/cadc -r /opt/astroai/cadc-tools.txt \
    && bash /tmp/patch-clint-py313.sh /opt/astroai/venv/cadc \
    && rm /tmp/patch-clint-py313.sh \
    && chmod -R a+rX /opt/astroai/venv/cadc

COPY scripts/lib/astroai-env-common.sh scripts/lib/astroai-ui.sh scripts/lib/astroai-load.sh scripts/lib/skaha-proxy.sh /opt/astroai/lib/
COPY scripts/astroai-env-save scripts/astroai-env-resume scripts/astroai-env-list \
    scripts/astroai-home-usage scripts/astroai-cache-prune \
    scripts/astroai-help.sh scripts/astroai-status.sh scripts/astroai-new.sh \
    scripts/astroai-clone.sh scripts/astroai-debug.sh scripts/astroai-install.sh \
    scripts/astroai-session-archive.sh scripts/astroai-data-sync.sh \
    scripts/astroai-project-init.sh scripts/astroai-kernel-register scripts/canfar-verify.sh \
    /opt/astroai/bin/
RUN chmod a+rx /opt/astroai/bin/* /opt/astroai/lib/* \
    && ln -sf astroai-help.sh /opt/astroai/bin/astroai-help \
    && ln -sf astroai-status.sh /opt/astroai/bin/astroai-status \
    && ln -sf astroai-new.sh /opt/astroai/bin/astroai-new \
    && ln -sf astroai-clone.sh /opt/astroai/bin/astroai-clone \
    && ln -sf astroai-debug.sh /opt/astroai/bin/astroai-debug \
    && ln -sf astroai-install.sh /opt/astroai/bin/astroai-install \
    && ln -sf astroai-session-archive.sh /opt/astroai/bin/astroai-session-archive \
    && ln -sf astroai-data-sync.sh /opt/astroai/bin/astroai-data-stage \
    && ln -sf astroai-data-sync.sh /opt/astroai/bin/astroai-data-sync \
    && ln -sf astroai-project-init.sh /opt/astroai/bin/astroai-project-init

COPY docs/USAGE.md /opt/astroai/USAGE.md
