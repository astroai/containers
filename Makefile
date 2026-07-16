.PHONY: help build-all build/% build-ray push-all push/% push-ray test-local test-ray test-canfar test-canfar-session test-canfar-ray test-canfar-ray-gpu clean clean-all lock-ray lock-astroai-lab lock-check

SHELL := bash
OWNER ?= astroai
REGISTRY ?= images.canfar.net
TAG ?= $(shell date -u +%y.%m)
BUILD_TAG ?= local
PYTHON_VERSION ?= 3.13

export OWNER REGISTRY PYTHON_VERSION

SESSION_IMAGES := base webterm notebook vscode marimo
RAY_IMAGES := ray-manager ray-worker
IMAGE_PREFIX := $(REGISTRY)/$(OWNER)

help:
	@echo "AstroAI session images (CANFAR Harbor: images.canfar.net/astroai)"
	@echo "========================="
	@echo "  make build-all          build session images (python → base → sessions)"
	@echo "  make build-ray          build ray-manager + ray-worker (+ base chain)"
	@echo "  make build/vscode       build one image (+ parents)"
	@echo "  make push-all           push session images to Harbor"
	@echo "  make push-ray           push Ray images to Harbor"
	@echo "  make test-local         verify session images locally"
	@echo "  make test-ray           Ray container + local cluster + UI tests"
	@echo "  make test-ray SMOKE=1   fast smoke: skip cluster formation"
	@echo "  make test-canfar        post-push headless verify on CANFAR"
	@echo "  make test-canfar-session post-push contributed/notebook HTTP smoke"
	@echo "  make test-canfar-ray    CANFAR: manager UI + 2-worker cluster lifecycle"
	@echo "  make test-canfar-ray-gpu CANFAR: 1 GPU worker cluster (production)"
	@echo "  make clean              remove local $(IMAGE_PREFIX)/* images"
	@echo "  make clean-all          clean + prune buildx cache"
	@echo "  make lock-ray           regenerate config/ray-deps.lock"
	@echo "  make lock-astroai-lab   regenerate config/astroai-lab.lock"
	@echo "  make lock-check         fail if a lockfile drifts from its source"
	@echo ""
	@echo "  OWNER=$(OWNER)  REGISTRY=$(REGISTRY)  BUILD_TAG=$(BUILD_TAG)  TAG=$(TAG)"

build-all: ## build session images
	TAG=$(BUILD_TAG) docker buildx bake

build-ray: ## build Ray manager + worker (uses same base TAG)
	TAG=$(BUILD_TAG) docker buildx bake ray-manager ray-worker

build/%:
	TAG=$(BUILD_TAG) docker buildx bake $(notdir $@)

push-all: $(addprefix push/,$(SESSION_IMAGES))

push-ray: $(addprefix push/,$(RAY_IMAGES))

# Production Ray push: bake TAG into manager env (RAY_IMAGE_TAG) — use BUILD_TAG=$(TAG).
#   make build-ray BUILD_TAG=26.06 TAG=26.06 && make push-ray TAG=26.06 BUILD_TAG=26.06

push/python:
	@echo "ERROR: python image is build-only (internal bake parent); never push to Harbor." >&2
	@exit 1

push/ray-base:
	@echo "ERROR: ray-base is build-only; push ray-manager and ray-worker." >&2
	@exit 1

push/%:
	docker tag $(IMAGE_PREFIX)/$(notdir $@):$(BUILD_TAG) $(IMAGE_PREFIX)/$(notdir $@):$(TAG)
	docker push $(IMAGE_PREFIX)/$(notdir $@):$(TAG)
	docker tag $(IMAGE_PREFIX)/$(notdir $@):$(BUILD_TAG) $(IMAGE_PREFIX)/$(notdir $@):latest
	docker push $(IMAGE_PREFIX)/$(notdir $@):latest

lock-ray: ## regenerate config/ray-deps.lock from config/ray-deps.txt (Python 3.12, Ray).
	uv pip compile --python-version 3.12 --output-file config/ray-deps.lock config/ray-deps.txt

lock-astroai-lab: ## regenerate config/astroai-lab.lock from the SHA pin in config/astroai-lab.in.
	uv pip compile --python-version 3.13 --output-file config/astroai-lab.lock config/astroai-lab.in

lock-check: ## fail CI if either lockfile's package body drifts from its source. The uv-generated header (3 lines) is stripped before comparison so output paths in the embedded command line don't cause false-positive drift.
	uv pip compile --python-version 3.12 --output-file /tmp/__ray.lock config/ray-deps.txt
	tail -n +4 /tmp/__ray.lock > /tmp/__ray.body
	tail -n +4 config/ray-deps.lock > /tmp/__ray.committed.body
	cmp -s /tmp/__ray.body /tmp/__ray.committed.body || { echo "ray-deps.lock drift — run make lock-ray" >&2; exit 1; }
	uv pip compile --python-version 3.13 --output-file /tmp/__lab.lock config/astroai-lab.in
	tail -n +4 /tmp/__lab.lock > /tmp/__lab.body
	tail -n +4 config/astroai-lab.lock > /tmp/__lab.committed.body
	cmp -s /tmp/__lab.body /tmp/__lab.committed.body || { echo "astroai-lab.lock drift — run make lock-astroai-lab" >&2; exit 1; }
	@echo "lockfile package bodies match their source constraints"

test-local: ## verify session images (parallel)
	@fails=0; pids=(); \
	for img in webterm notebook vscode marimo base; do \
		./scripts/test-local.sh "$$img" --verify-only & pids+=($$!); \
	done; \
	for pid in "$${pids[@]}"; do wait "$$pid" || fails=$$((fails + 1)); done; \
	if [[ "$$fails" -gt 0 ]]; then echo "$$fails image(s) failed." >&2; exit 1; fi
	./scripts/test-status-arc-project.sh

test-ray: build-ray build/base ## Ray image checks + local cluster join + UI
	chmod +x scripts/test-ray-*.sh scripts/test-astroai-lab-loop.sh scripts/ray-head-start.sh \
		scripts/startup-ray-manager.sh scripts/ray-network-probe.sh ray/worker/start-worker.sh
	./scripts/test-ray-containers.sh $(if $(filter 1,$(SMOKE)),--smoke,)
	./scripts/test-ray-local.sh $(if $(filter 1,$(SMOKE)),--smoke,)
	./scripts/test-ray-cluster-local.sh $(if $(filter 1,$(SMOKE)),--smoke,)
	./scripts/test-ray-ui-local.sh $(if $(filter 1,$(SMOKE)),--smoke,)
	./scripts/test-astroai-lab-loop.sh $(if $(filter 1,$(SMOKE)),--smoke,)

test-canfar:
	./scripts/test-canfar.sh $(or $(IMAGE),base) $(TAG)

test-canfar-session: ## contributed/notebook Running + connectURL HTTP smoke
	chmod +x scripts/test-canfar-session.sh
	./scripts/test-canfar-session.sh $(or $(IMAGE),webterm) $(TAG)

test-canfar-ray: ## CANFAR manager UI + 2-worker cluster lifecycle
	chmod +x scripts/test-canfar-ray.sh
	./scripts/test-canfar-ray.sh $(TAG)

test-canfar-ray-gpu: ## CANFAR 1-worker cluster with gpu=1
	chmod +x scripts/test-canfar-ray.sh
	CANFAR_RAY_GPUS=1 CANFAR_RAY_WORKER_COUNT=1 CANFAR_RAY_MIN_JOINED=1 \
		./scripts/test-canfar-ray.sh $(TAG)

clean:
	@imgs=($$(docker images --format '{{.Repository}}:{{.Tag}}' '$(IMAGE_PREFIX)/*' 2>/dev/null || true)); \
	if [[ $${#imgs[@]} -eq 0 || -z "$${imgs[0]}" ]]; then \
		echo "No $(IMAGE_PREFIX)/* images to remove."; \
	else \
		for img in "$${imgs[@]}"; do \
			docker rmi -f "$$img" 2>/dev/null || true; \
		done; \
		echo "Removed $(IMAGE_PREFIX)/* images."; \
	fi

clean-all: clean
	docker buildx prune -f

.PHONY: ray-launch
ray-launch:
	./scripts/ray-launch.sh
