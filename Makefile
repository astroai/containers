.PHONY: help build-all build/% push-all push/% test-canfar test-local clean clean-all

SHELL := bash
OWNER ?= astroai
REGISTRY ?= images.canfar.net
TAG ?= $(shell date -u +%y.%m)
BUILD_TAG ?= local
PYTHON_VERSION ?= 3.13

export OWNER REGISTRY PYTHON_VERSION

ALL_IMAGES := base webterm notebook vscode marimo full
IMAGE_PREFIX := $(REGISTRY)/$(OWNER)

help:
	@echo "AstroAI CANFAR containers"
	@echo "========================="
	@echo "  make build-all          build full stack"
	@echo "  make build/vscode       build one image (+ parents)"
	@echo "  make push-all           tag and push all images to Harbor"
	@echo "  make push/vscode        tag and push one image to Harbor"
	@echo "  make test-local         local smoke test (webterm/notebook)"
	@echo "  make test-canfar        post-push headless verify on CANFAR (needs canfar auth)"
	@echo "  make clean              remove local $(IMAGE_PREFIX)/* images"
	@echo "  make clean-all          clean + prune buildx cache"
	@echo ""
	@echo "  OWNER=$(OWNER)  REGISTRY=$(REGISTRY)  BUILD_TAG=$(BUILD_TAG)  TAG=$(TAG)"

build-all: ## build all session images
	TAG=$(BUILD_TAG) docker buildx bake

build/%:
	TAG=$(BUILD_TAG) docker buildx bake $(notdir $@)

push-all: push/python $(addprefix push/,$(ALL_IMAGES))

push/python:
	docker push $(REGISTRY)/$(OWNER)/python:$(PYTHON_VERSION)

push/%:
	docker tag $(REGISTRY)/$(OWNER)/$(notdir $@):$(BUILD_TAG) $(REGISTRY)/$(OWNER)/$(notdir $@):$(TAG)
	docker push $(REGISTRY)/$(OWNER)/$(notdir $@):$(TAG)
	docker tag $(REGISTRY)/$(OWNER)/$(notdir $@):$(BUILD_TAG) $(REGISTRY)/$(OWNER)/$(notdir $@):latest
	docker push $(REGISTRY)/$(OWNER)/$(notdir $@):latest

test-local: ## local smoke test (webterm + notebook PATH checks)
	./scripts/test-local.sh webterm --verify-only
	./scripts/test-local.sh notebook --verify-only

test-canfar: ## post-push headless verification on CANFAR (IMAGE=base TAG=$(TAG))
	./scripts/test-canfar.sh $(or $(IMAGE),base) $(TAG)

clean: ## remove locally built AstroAI images
	@imgs=($$(docker images --format '{{.Repository}}:{{.Tag}}' '$(IMAGE_PREFIX)/*' 2>/dev/null || true)); \
	if [[ $${#imgs[@]} -eq 0 || -z "$${imgs[0]}" ]]; then \
		echo "No $(IMAGE_PREFIX)/* images to remove."; \
	else \
		for img in "$${imgs[@]}"; do \
			docker rmi -f "$$img" 2>/dev/null || true; \
		done; \
		echo "Removed $(IMAGE_PREFIX)/* images."; \
	fi

clean-all: clean ## remove images and buildx build cache
	docker buildx prune -f
