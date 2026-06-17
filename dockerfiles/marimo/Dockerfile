# syntax=docker/dockerfile:1
# AstroAI marimo: reactive notebooks.

ARG REGISTRY=images.canfar.net
ARG OWNER=astroai
ARG BASE_NAME=base
ARG TAG=local

FROM ${REGISTRY}/${OWNER}/${BASE_NAME}:${TAG}

LABEL io.canfar.skaha.session.type="contributed"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN uv pip install --system marimo

COPY scripts/common-init.sh scripts/startup-marimo.sh /cadc/
COPY scripts/skaha-startup-marimo.sh /skaha/startup.sh
RUN chmod a+rx /cadc/*.sh /skaha/startup.sh

EXPOSE 5000
WORKDIR /tmp
CMD ["/cadc/startup-marimo.sh"]
