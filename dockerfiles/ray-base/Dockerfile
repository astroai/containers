# syntax=docker/dockerfile:1
# Ray common layer — extends astroai/base (shared CADC, canfar-lab, session profile).

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/base:${TAG}

LABEL org.opencontainers.image.title="AstroAI Ray Base" \
      org.opencontainers.image.description="Ray + astronomy deps on AstroAI base"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY config/ray-deps.txt /opt/astroai/ray-deps.txt
RUN uv python install 3.12 \
    && uv venv /opt/astroai/venv/ray --python 3.12 \
    && uv pip install --python /opt/astroai/venv/ray -r /opt/astroai/ray-deps.txt \
    && rm /opt/astroai/ray-deps.txt \
    && /opt/astroai/venv/ray/bin/python -c "import ray; print(ray.__version__)" \
        > /opt/astroai/ray-version.txt \
    && chmod a+r /opt/astroai/ray-version.txt \
    && /opt/astroai/venv/ray/bin/python -c "import ray; print('ray', ray.__version__)"

ENV PATH="/opt/astroai/venv/ray/bin:/opt/astroai/venv/cadc/bin:${PATH}"

COPY ray/worker/start-worker.sh /opt/astroai/bin/start-ray-worker.sh
COPY scripts/ray-head-start.sh /opt/astroai/bin/ray-head-start.sh
COPY scripts/ray-network-probe.sh /opt/astroai/bin/ray-network-probe.sh
COPY scripts/lib/ray-version.sh /opt/astroai/lib/ray-version.sh
COPY examples/ray/ /opt/astroai/examples/ray/
RUN chmod a+rx /opt/astroai/bin/start-ray-worker.sh /opt/astroai/bin/ray-head-start.sh \
    /opt/astroai/bin/ray-network-probe.sh \
    && chmod a+rx /opt/astroai/lib/ray-version.sh
