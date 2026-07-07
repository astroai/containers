# AstroAI container stack — build with: docker buildx bake

variable "REGISTRY" {
  default = "images.canfar.net"
}

variable "OWNER" {
  default = "astroai"
}

variable "TAG" {
  default = "local"
}

variable "PYTHON_VERSION" {
  default = "3.13"
}

group "default" {
  targets = ["base", "webterm", "notebook", "vscode", "marimo"]
}

target "python" {
  context    = "./dockerfiles/python"
  dockerfile = "Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}"]
  args = {
    PYTHON_VERSION = "${PYTHON_VERSION}"
  }
}

target "base" {
  context    = "."
  dockerfile = "dockerfiles/base/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/python:${PYTHON_VERSION}" = "target:python"
  }
  tags = ["${REGISTRY}/${OWNER}/base:${TAG}"]
  args = {
    REGISTRY       = "${REGISTRY}"
    OWNER          = "${OWNER}"
    PYTHON_VERSION = "${PYTHON_VERSION}"
  }
}

target "_interface" {
  context = "."
  contexts = {
    "${REGISTRY}/${OWNER}/base:${TAG}" = "target:base"
  }
  args = {
    REGISTRY  = "${REGISTRY}"
    OWNER     = "${OWNER}"
    BASE_NAME = "base"
    TAG       = "${TAG}"
  }
}

target "webterm" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/webterm/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/webterm:${TAG}"]
}

target "notebook" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/notebook/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/notebook:${TAG}"]
}

target "vscode" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/vscode/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/vscode:${TAG}"]
}

target "marimo" {
  inherits   = ["_interface"]
  dockerfile = "dockerfiles/marimo/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/marimo:${TAG}"]
}

# Ray cluster images (extend base in same bake — shared TAG/deps)
target "ray-base" {
  context    = "."
  dockerfile = "dockerfiles/ray-base/Dockerfile"
  contexts = {
    "${REGISTRY}/${OWNER}/base:${TAG}" = "target:base"
  }
  tags = ["${REGISTRY}/${OWNER}/ray-base:${TAG}"]
  args = {
    REGISTRY = "${REGISTRY}"
    OWNER    = "${OWNER}"
    TAG      = "${TAG}"
  }
}

target "_ray" {
  context = "."
  contexts = {
    "${REGISTRY}/${OWNER}/ray-base:${TAG}" = "target:ray-base"
  }
  args = {
    REGISTRY = "${REGISTRY}"
    OWNER    = "${OWNER}"
    TAG      = "${TAG}"
  }
}

target "ray-manager" {
  inherits   = ["_ray"]
  dockerfile = "dockerfiles/ray-manager/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/ray-manager:${TAG}"]
}

target "ray-worker" {
  inherits   = ["_ray"]
  dockerfile = "dockerfiles/ray-worker/Dockerfile"
  tags       = ["${REGISTRY}/${OWNER}/ray-worker:${TAG}"]
}
