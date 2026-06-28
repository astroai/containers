# syntax=docker/dockerfile:1
# AstroAI base: platform CLI + monitoring + compression. No browser UI.
#
# Apt packages: root-only tools not practical via pixi/uv/micromamba.
# GCC + Rust + autotools, common astronomy headers; heavy ML stacks stay in pixi.

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
    autoconf \
    automake \
    bash-completion \
    bat \
    bind9-dnsutils \
    bison \
    bsdextrautils \
    build-essential \
    bzip2 \
    ca-certificates \
    cargo \
    cmake \
    curl \
    fd-find \
    file \
    flex \
    fzf \
    gfortran \
    gh \
    git \
    git-delta \
    git-lfs \
    htop \
    hyperfine \
    iproute2 \
    jq \
    less \
    libcfitsio-dev \
    libfftw3-dev \
    libgsl-dev \
    libtool \
    locales \
    lsof \
    make \
    ncdu \
    ninja-build \
    nvtop \
    openssh-client \
    patch \
    pigz \
    pkg-config \
    procps \
    ripgrep \
    rsync \
    rustc \
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
    SHELL=/bin/bash \
    CANFAR_LAB_DEFAULT_SRC_DIR=/srcdir \
    CANFAR_LAB_DEFAULT_SCRATCH_DIR=/scratch

RUN printf '%s\n' \
    '[ -f /etc/profile.d/astroai.sh ] && . /etc/profile.d/astroai.sh' \
    >> /etc/bash.bashrc

COPY scripts/astroai-profile.sh /etc/profile.d/astroai.sh
RUN chmod a+r /etc/profile.d/astroai.sh

RUN mkdir -p /opt/astroai/{bin,cache,lib,venv} /cadc "${CANFAR_LAB_DEFAULT_SRC_DIR}" \
    && chmod -R a+rX /opt/astroai \
    && chmod -R a+rwx /opt/astroai/cache \
    && chmod 1777 "${CANFAR_LAB_DEFAULT_SRC_DIR}"

COPY config/cadc-tools.txt /opt/astroai/cadc-tools.txt
COPY vendor/canfar_lab-0.1.0-py3-none-any.whl /tmp/canfar_lab-0.1.0-py3-none-any.whl
COPY scripts/patch-clint-py313.sh /tmp/patch-clint-py313.sh
RUN uv venv /opt/astroai/venv/cadc \
    && uv pip install --python /opt/astroai/venv/cadc -r /opt/astroai/cadc-tools.txt \
    && uv pip install --python /opt/astroai/venv/cadc /tmp/canfar_lab-0.1.0-py3-none-any.whl \
    && bash /tmp/patch-clint-py313.sh /opt/astroai/venv/cadc \
    && rm /tmp/patch-clint-py313.sh /tmp/canfar_lab-0.1.0-py3-none-any.whl \
    && chmod -R a+rX /opt/astroai/venv/cadc \
    && /opt/astroai/venv/cadc/bin/canfar-lab env install-shell /etc/canfar-lab \
    && test -f /etc/canfar-lab/profile.sh \
    && test -f /etc/canfar-lab/hooks.sh \
    && HOME=/tmp CANFAR_LAB_DEFAULT_SRC_DIR=/srcdir CANFAR_LAB_DEFAULT_SCRATCH_DIR=/scratch \
       /opt/astroai/venv/cadc/bin/canfar-lab env export --no-ensure >/dev/null

COPY scripts/lib/astroai-env-common.sh scripts/lib/astroai-ui.sh scripts/lib/astroai-load.sh scripts/lib/skaha-proxy.sh /opt/astroai/lib/
COPY scripts/canfar-verify.sh scripts/canfar-verify-agents.sh /opt/astroai/bin/
RUN chmod a+rx /opt/astroai/bin/* /opt/astroai/lib/*

COPY docs/USAGE.md /opt/astroai/USAGE.md
