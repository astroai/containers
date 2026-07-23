# syntax=docker/dockerfile:1
# AstroAI openresearch: OpenResearch (orx) autoresearch dashboard.
# Prebuilt release binary only — no cargo rebuild. Proxies :4791 → :5000.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local
ARG ORX_VERSION=0.1.76
ARG ORX_SHA256_X64=8bc1d10c1a511ecb4935e4eac911b6525c7e8c051b9302422859a6fe26bfe93d
ARG ORX_SHA256_ARM64=0e8c7d000db569102f47a17d062478f7b376e59b30f2b2b1d27b86e7dc5ab41f

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

ARG ORX_VERSION
ARG ORX_SHA256_X64
ARG ORX_SHA256_ARM64

LABEL io.canfar.skaha.session.type="contributed" \
      org.opencontainers.image.title="AstroAI OpenResearch" \
      org.opencontainers.image.description="OpenResearch (orx) autoresearch dashboard for CANFAR" \
      org.opencontainers.image.source="https://github.com/alphaXiv/openresearch-cli"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# No socat — path-rewriting proxy is scripts/lib/orx-canfar-proxy.py (stdlib).

RUN ARCH="$(uname -m)" \
    && case "${ARCH}" in \
        x86_64) TRIPLE=x86_64-unknown-linux-musl; SHA256="${ORX_SHA256_X64}" ;; \
        aarch64) TRIPLE=aarch64-unknown-linux-musl; SHA256="${ORX_SHA256_ARM64}" ;; \
        *) echo "unsupported arch: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && TARBALL="openresearch-cli-${TRIPLE}.tar.xz" \
    && curl -fsSL -o "${TARBALL}" \
        "https://github.com/alphaXiv/openresearch-cli/releases/download/v${ORX_VERSION}/${TARBALL}" \
    && echo "${SHA256}  ${TARBALL}" | sha256sum -c - \
    && tar -xJf "${TARBALL}" \
    && install -m 0755 "openresearch-cli-${TRIPLE}/orx" /opt/astroai/bin/orx \
    && rm -rf "${TARBALL}" "openresearch-cli-${TRIPLE}" \
    && /opt/astroai/bin/orx --version

ENV PATH="/opt/astroai/bin:${PATH}" \
    ORX_NO_UPDATE_CHECK=1 \
    ASTROAI_SESSION_KIND=openresearch

COPY scripts/lib/skaha-proxy.sh scripts/lib/orx-canfar-proxy.py /opt/astroai/lib/
COPY scripts/common-init.sh scripts/startup-openresearch.sh /cadc/
COPY scripts/skaha-startup-openresearch.sh /skaha/startup.sh
RUN chmod a+rx /opt/astroai/lib/orx-canfar-proxy.py /cadc/*.sh /skaha/startup.sh \
    && chmod a+r /opt/astroai/lib/skaha-proxy.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/ >/dev/null

WORKDIR /tmp
CMD ["/skaha/startup.sh"]
