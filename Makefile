.PHONY: help build-all build/% build-ray push-all push/% push-ray test-local test-ray test-canfar test-canfar-ray clean clean-all

SHELL := bash
OWNER ?= astroai
REGISTRY ?= images.canfar.net
TAG ?= $(shell date -u +%y.%m)
BUILD_TAG ?= local
PYTHON_VERSION ?= 3.13

export OWNER REGISTRY PYTHON_VERSION

SESSION_IMAGES := base webterm notebook vscode marimo
RAY_IMAGES := ray-manager ray-worker-cpu
IMAGE_PREFIX := $(REGISTRY)/$(OWNER)

help:
	@echo "AstroAI CANFAR containers"
	@echo "========================="
	@echo "  make build-all          build session images (python → base → sessions)"
	@echo "  make build-ray          build ray-manager + ray-worker-cpu (+ base chain)"
	@echo "  make build/vscode       build one image (+ parents)"
	@echo "  make push-all           push session images to Harbor"
	@echo "  make push-ray           push Ray images to Harbor"
	@echo "  make test-local         verify session images locally"
	@echo "  make test-ray           Ray container + local cluster + UI tests"
	@echo "  make test-canfar        post-push headless verify on CANFAR"
	@echo "  make test-canfar-ray    CANFAR: manager UI + 2-worker cluster lifecycle"
	@echo "  make clean              remove local $(IMAGE_PREFIX)/* images"
	@echo "  make clean-all          clean + prune buildx cache"
	@echo ""
	@echo "  OWNER=$(OWNER)  REGISTRY=$(REGISTRY)  BUILD_TAG=$(BUILD_TAG)  TAG=$(TAG)"

build-all: ## build session images
	TAG=$(BUILD_TAG) docker buildx bake

build-ray: ## build Ray manager + worker (uses same base TAG)
	TAG=$(BUILD_TAG) docker buildx bake ray-manager ray-worker-cpu

build/%:
	TAG=$(BUILD_TAG) docker buildx bake $(notdir $@)

push-all: $(addprefix push/,$(SESSION_IMAGES))

push-ray: $(addprefix push/,$(RAY_IMAGES))

push/python:
	@echo "ERROR: python image is build-only (internal bake parent); never push to Harbor." >&2
	@exit 1

push/ray-base:
	@echo "ERROR: ray-base is build-only; push ray-manager and ray-worker-cpu." >&2
	@exit 1

push/%:
	docker tag $(IMAGE_PREFIX)/$(notdir $@):$(BUILD_TAG) $(IMAGE_PREFIX)/$(notdir $@):$(TAG)
	docker push $(IMAGE_PREFIX)/$(notdir $@):$(TAG)
	docker tag $(IMAGE_PREFIX)/$(notdir $@):$(BUILD_TAG) $(IMAGE_PREFIX)/$(notdir $@):latest
	docker push $(IMAGE_PREFIX)/$(notdir $@):latest

test-local: ## verify session images
	@for img in webterm notebook vscode marimo base; do \
		./scripts/test-local.sh "$$img" --verify-only || exit 1; \
	done

test-ray: build-ray build/base ## Ray image checks + local cluster join + UI
	chmod +x scripts/test-ray-*.sh scripts/test-canfar-lab-loop.sh scripts/ray-head-start.sh \
		scripts/startup-ray-manager.sh scripts/ray-network-probe.sh ray/worker/start-worker.sh
	./scripts/test-ray-containers.sh
	./scripts/test-ray-local.sh
	./scripts/test-ray-cluster-local.sh
	./scripts/test-ray-ui-local.sh
	./scripts/test-canfar-lab-loop.sh

test-canfar:
	./scripts/test-canfar.sh $(or $(IMAGE),base) $(TAG)

test-canfar-ray: ## CANFAR manager UI + 2-worker cluster lifecycle
	chmod +x scripts/test-canfar-ray.sh
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
