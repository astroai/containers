# syntax=docker/dockerfile:1
# Ray Manager — contributed session (port 5000) + Ray head.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/ray-base:${TAG}

LABEL io.canfar.skaha.session.type="contributed"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY ray/manager/ /opt/astroai/ray-manager/
COPY scripts/startup-ray-manager.sh /skaha/startup.sh
RUN uv pip install --python /opt/astroai/venv/ray \
        "canfar==1.4.1" \
        "fastapi>=0.115.0" "uvicorn[standard]>=0.32.0" "python-multipart>=0.0.9" \
    && chmod a+rx /skaha/startup.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/healthz >/dev/null

WORKDIR /tmp
CMD ["/skaha/startup.sh"]
