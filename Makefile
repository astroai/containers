.PHONY: help build-all build/% push/% clean clean-all

SHELL := bash
OWNER ?= astroai
REGISTRY ?= images.canfar.net
TAG ?= $(shell date -u +%y.%m)
PYTHON_VERSION ?= 3.13

export OWNER REGISTRY TAG

ALL_IMAGES := base webterm notebook vscode marimo
IMAGE_PREFIX := $(REGISTRY)/$(OWNER)

help:
	@echo "AstroAI CANFAR containers"
	@echo "========================="
	@echo "  make build-all          build full stack"
	@echo "  make build/vscode       build one image (+ parents)"
	@echo "  make push/vscode        tag and push to Harbor"
	@echo "  make clean              remove local $(IMAGE_PREFIX)/* images"
	@echo "  make clean-all          clean + prune buildx cache"
	@echo ""
	@echo "  OWNER=$(OWNER)  REGISTRY=$(REGISTRY)  TAG=$(TAG)"

build-all: ## build all session images
	docker buildx bake

build/%:
	docker buildx bake $(notdir $@)

push/%:
	docker tag $(REGISTRY)/$(OWNER)/$(notdir $@):local $(REGISTRY)/$(OWNER)/$(notdir $@):$(TAG)
	docker push $(REGISTRY)/$(OWNER)/$(notdir $@):$(TAG)
	docker tag $(REGISTRY)/$(OWNER)/$(notdir $@):local $(REGISTRY)/$(OWNER)/$(notdir $@):latest
	docker push $(REGISTRY)/$(OWNER)/$(notdir $@):latest

clean: ## remove locally built AstroAI images
	@imgs=("$$(docker images --format '{{.Repository}}:{{.Tag}}' '$(IMAGE_PREFIX)/*' 2>/dev/null || true)"); \
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
