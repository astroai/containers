.PHONY: help build-all build/% push/%

SHELL := bash
OWNER ?= astroai
REGISTRY ?= images.canfar.net
TAG ?= $(shell date -u +%y.%m)

export OWNER REGISTRY TAG

ALL_IMAGES := base webterm notebook vscode marimo

help:
	@echo "AstroAI CANFAR containers"
	@echo "========================="
	@echo "  make build-all          build full stack"
	@echo "  make build/vscode       build one image (+ parents)"
	@echo "  make push/vscode        tag and push to Harbor"
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
