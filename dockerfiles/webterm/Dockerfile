# syntax=docker/dockerfile:1
# AstroAI webterm: browser shell via ttyd + tmux.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
ARG TTYD_VERSION=1.7.7
ARG STARSHIP_VERSION=1.25.1
ARG STARSHIP_SHA256_X64=c6ddd3ecb9c0071a2ad38d98cee748160066b7c4f197421268058f4a5d6f8504
ARG STARSHIP_SHA256_ARM64=01517aab398959ea9ea73bdb4f032ea4dbb51dff5c8e5eb05b4a1b9b7ab872b8

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

ARG TTYD_VERSION
ARG STARSHIP_VERSION
ARG STARSHIP_SHA256_X64
ARG STARSHIP_SHA256_ARM64

LABEL io.canfar.skaha.session.type="contributed"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux \
    && rm -rf /var/lib/apt/lists/*

COPY dockerfiles/install-ttyd.sh /tmp/install-ttyd.sh
RUN chmod a+rx /tmp/install-ttyd.sh \
    && /tmp/install-ttyd.sh "${TTYD_VERSION}" \
    && rm /tmp/install-ttyd.sh

RUN ARCH="$(uname -m)" \
    && case "${ARCH}" in \
        x86_64) TRIPLE=x86_64-unknown-linux-musl; SHA256="${STARSHIP_SHA256_X64}" ;; \
        aarch64) TRIPLE=aarch64-unknown-linux-musl; SHA256="${STARSHIP_SHA256_ARM64}" ;; \
        *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && TARBALL="starship-${TRIPLE}.tar.gz" \
    && curl -fsSL -o "${TARBALL}" \
        "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/${TARBALL}" \
    && echo "${SHA256}  ${TARBALL}" | sha256sum -c - \
    && tar -xzf "${TARBALL}" -C /usr/local/bin \
    && rm "${TARBALL}" \
    && starship --version \
    && { printf '%s\n' \
        '# Bash-only (/etc/profile sources profile.d for all login shells, including sh).' \
        'if [ -z "${BASH_VERSION:-}" ]; then' \
        '    return 0 2>/dev/null || exit 0' \
        'fi' \
        'export STARSHIP_CONFIG=/etc/starship.toml'; \
       /usr/local/bin/starship init bash --print-full-init; \
    } > /etc/profile.d/starship.sh \
    && chmod a+r /etc/profile.d/starship.sh

RUN printf '%s\n' \
    'set -g default-shell /bin/bash' \
    'set -g mouse on' \
    'set -g history-limit 50000' \
    'set -g status-interval 5' \
    'set -g status-position top' \
    'set -g status-left-length 20' \
    'set -g status-left "#[fg=colour117,bold]AstroAI"' \
    'set -g status-right "#[fg=colour245]#{host_short}"' \
    'setw -g window-status-format " #[fg=colour245,bold]#I#[fg=colour245]:#[fg=colour252]#W "' \
    'setw -g window-status-current-format " #[fg=colour117,bold]#I#[fg=colour117]:#[fg=colour255,bold]#W "' \
    'setw -g window-status-separator ""' \
    'set -s set-clipboard on' \
    'set -g allow-passthrough on' \
    'setw -g mode-keys vi' \
    > /etc/tmux.conf

COPY config/starship.toml /etc/starship.toml
COPY scripts/build-custom-webterm-ui.py /tmp/build-custom-webterm-ui.py
RUN mkdir -p /cadc \
    && python3 /tmp/build-custom-webterm-ui.py /cadc/index.html \
    && rm /tmp/build-custom-webterm-ui.py

COPY scripts/common-init.sh scripts/startup-webterm.sh /cadc/
COPY scripts/skaha-startup-webterm.sh /skaha/startup.sh
RUN chmod a+rx /cadc/*.sh /skaha/startup.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/ >/dev/null

WORKDIR /tmp
CMD ["/skaha/startup.sh"]
