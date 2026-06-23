# syntax=docker/dockerfile:1
# AstroAI webterm: browser shell via ttyd + tmux.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local

FROM tsl0922/ttyd:1.7.7 AS ttyd-bin

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

LABEL io.canfar.skaha.session.type="contributed"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    tmux \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ttyd-bin /usr/bin/ttyd /usr/local/bin/ttyd

RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes \
    && { printf '%s\n' \
        '# Bash-only (/etc/profile sources profile.d for all login shells, including sh).' \
        'if [ -z "${BASH_VERSION:-}" ]; then' \
        '    return 0 2>/dev/null || exit 0' \
        'fi'; \
       /usr/local/bin/starship init bash --print-full-init; \
    } > /etc/profile.d/starship.sh \
    && chmod a+r /etc/profile.d/starship.sh

RUN printf '%s\n' \
    'set -g default-shell /bin/bash' \
    'set -g mouse off' \
    'set -g history-limit 50000' \
    'set -g status off' \
    > /etc/tmux.conf

COPY scripts/common-init.sh scripts/startup-webterm.sh /cadc/
COPY scripts/skaha-startup-webterm.sh /skaha/startup.sh
RUN chmod a+rx /cadc/*.sh /skaha/startup.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/ >/dev/null

WORKDIR /tmp
CMD ["/cadc/startup-webterm.sh"]
