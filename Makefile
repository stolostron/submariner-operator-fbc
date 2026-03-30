# ============================================================================
# Variables & Configuration
# ============================================================================
LOCAL_BIN ?= $(PWD)/bin
export PATH := $(LOCAL_BIN):$(PATH)
GOOS := $(shell go env GOOS)
GOARCH := $(shell go env GOARCH)

# Shellcheck configuration
SHELLCHECK_ARGS += $(shell find . -name "*.sh" -type f ! -path "./.git/*" ! -path "./bin/*")
export SHELLCHECK_ARGS

# Image configuration
VERSION_TAG ?= latest
IMG_REPO ?= quay.io/stolostron
IMAGE_TAG_BASE ?= $(IMG_REPO)/submariner-operator-fbc
IMG ?= $(IMAGE_TAG_BASE):$(VERSION_TAG)

# ============================================================================
# Default Target & Help
# ============================================================================
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Submariner Operator FBC"
	@echo ""
	@echo "Main workflow:"
	@echo "  update-bundle       Add/update bundle (VERSION=X.Y.Z [SNAPSHOT=...] [REPLACE=...])"
	@echo ""
	@echo "Catalogs:"
	@echo "  build-catalogs      Generate all OCP catalogs from template"
	@echo "  validate-catalogs   Validate catalogs with opm"
	@echo "  fetch-catalog       Extract production catalog ([OCP_VERSION=4.21] [PACKAGE=submariner])"
	@echo "  extract-image       Extract container image filesystem (IMAGE=<image> [OUTPUT_DIR=<path>])"
	@echo ""
	@echo "Container images:"
	@echo "  build-image         Build container image"
	@echo "  run-image           Build and run image on port 50051"
	@echo "  stop-image          Stop running image"
	@echo "  test-image          Build, run, and test image"
	@echo ""
	@echo "Testing & linting:"
	@echo "  test                Fast unit+integration tests (~10s)"
	@echo "  test-e2e            E2E tests (~5-15min, requires cluster)"
	@echo "  shellcheck          Lint shell scripts"
	@echo "  mdlint              Lint markdown files"
	@echo "  yamllint            Lint YAML files"
	@echo "  lint                Run all linting"
	@echo "  ci                  Run catalog validation, linting, and fast tests"
	@echo ""
	@echo "Tools:"
	@echo "  opm                 Ensure opm v1.56.0 is installed"
	@echo "  grpcurl             Ensure grpcurl v1.9.3 is installed"
	@echo "  clean               Clean build/test artifacts and restore from git"

# ============================================================================
# Main Workflow
# ============================================================================

# Update bundle in catalog (ADD/UPDATE/REPLACE scenarios)
# Note: Released bundles are auto-converted from quay.io to registry.redhat.io automatically
.PHONY: update-bundle
update-bundle:
	@if [ -z "$(VERSION)" ]; then \
		echo "ERROR: VERSION required"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make update-bundle VERSION=0.22.1                        # UPDATE scenario"; \
		echo "  make update-bundle VERSION=0.22.0                        # ADD scenario"; \
		echo "  make update-bundle VERSION=0.21.2 REPLACE=0.21.1         # REPLACE scenario"; \
		echo "  make update-bundle VERSION=0.22.1 SNAPSHOT=submariner-0-22-xxxxx  # Explicit snapshot"; \
		exit 1; \
	fi
	./scripts/update-bundle.sh --version "$(VERSION)" \
		$(if $(SNAPSHOT),--snapshot "$(SNAPSHOT)") \
		$(if $(REPLACE),--replace "$(REPLACE)")

# ============================================================================
# Catalog Operations
# ============================================================================

.PHONY: build-catalogs
build-catalogs: opm
	./build/build.sh

.PHONY: validate-catalogs
validate-catalogs: opm
	@for catalog in catalog-*/; do \
		echo "Validating $${catalog} ..."; \
		$(OPM) validate $${catalog}; \
	done

.PHONY: fetch-catalog
fetch-catalog:
	./scripts/fetch-catalog-containerized.sh "$${OCP_VERSION:-4.21}" "$${PACKAGE:-submariner}"

.PHONY: extract-image
extract-image:
	@if [ -z "$(IMAGE)" ]; then \
		echo "ERROR: IMAGE required"; \
		echo ""; \
		echo "Usage:"; \
		echo "  make extract-image IMAGE=<image_name:tag>"; \
		echo "  make extract-image IMAGE=<image_name:tag> OUTPUT_DIR=<path>"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make extract-image IMAGE=quay.io/stolostron/submariner-operator-fbc:latest"; \
		echo "  make extract-image IMAGE=registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:abc123 OUTPUT_DIR=/tmp/extracted"; \
		exit 1; \
	fi
	./scripts/image-extract.sh "$(IMAGE)" $(if $(OUTPUT_DIR),"$(OUTPUT_DIR)")

# ============================================================================
# Container Image Operations
# ============================================================================

.PHONY: build-image
build-image:
	podman build -t $(IMG) -f catalog.Dockerfile --build-arg INPUT_DIR=$$(find catalog-* -type d -maxdepth 0 | head -1) .

# ref: https://github.com/operator-framework/operator-registry?tab=readme-ov-file#using-the-catalog-locally
.PHONY: run-image
run-image: build-image
	$(MAKE) stop-image
	podman run -d -p 50051:50051 $(IMG) &

.PHONY: stop-image
stop-image:
	podman stop --filter "ancestor=$(IMG)"

.PHONY: test-image
test-image: run-image grpcurl
	@echo "# Checking availability of server endpoint"
	@connected=false; \
	for i in $$(seq 1 5); do \
		if $(GRPCURL) -plaintext localhost:50051 list > /dev/null 2>&1; then \
			echo "--> Connection successful on attempt $${i}."; \
			connected=true; \
			break; \
		else \
			echo "Connection failed. Retrying ($${i}/5)"; \
			sleep 3; \
		fi; \
	done; \
	if [ "$$connected" = false ]; then \
		echo "Error: Could not connect to the server after 5 attempts."; \
		exit 1; \
	fi
	@echo "# Validate package list"
	@echo "--> Comparing package list from running image with test/packageList.json"
	@actual_packages=$(mktemp); \
	$(GRPCURL) -plaintext localhost:50051 api.Registry.ListPackages > $actual_packages; \
	echo "--> Expected packages:"; \
	cat test/packageList.json; \
	echo "--> Actual packages from image:"; \
	cat $actual_packages; \
	if diff -u test/packageList.json $actual_packages; then \
		echo "--> Package list validation successful!"; \
	else \
		echo "--> Error: Package list validation failed."; \
		exit 1; \
	fi; \
	rm $actual_packages

# ============================================================================
# Testing
# ============================================================================

.PHONY: test
test: opm
	./test/test.sh

.PHONY: test-e2e
test-e2e: opm
	@echo "Running end-to-end tests (slow, requires cluster/network)..."
	@if [ -d "./test/e2e" ]; then \
		for test_script in ./test/e2e/test-*.sh; do \
			if [ -f "$$test_script" ]; then \
				echo ""; \
				echo "Running: $$test_script"; \
				"$$test_script"; \
			fi; \
		done; \
	fi

# ============================================================================
# Linting
# ============================================================================

.PHONY: shellcheck
shellcheck:
ifneq (,$(SHELLCHECK_ARGS))
	shellcheck -S warning $(SHELLCHECK_ARGS)
else
	@echo 'No shell scripts found to check.'
endif

.PHONY: mdlint
mdlint:
	npx markdownlint-cli2 "**/*.md"

.PHONY: yamllint
yamllint:
	yamllint .

.PHONY: lint
lint: shellcheck mdlint yamllint

# ============================================================================
# CI Composite Target
# ============================================================================

.PHONY: ci
ci: validate-catalogs lint test

# ============================================================================
# Tool Installation
# ============================================================================

OPM = $(LOCAL_BIN)/opm

$(OPM):
	mkdir -p $(@D)

.PHONY: opm
opm: $(OPM)
	# Checking installation of opm
	@pinned_release="v1.56.0"; \
	if ! $(OPM) version || [ "$$($(OPM) version | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)" != "$${pinned_release}" ]; then \
		echo "Installing opm $${pinned_release}"; \
		download_url="https://github.com/operator-framework/operator-registry/releases/download/$${pinned_release}/$(GOOS)-$(GOARCH)-opm"; \
		curl --fail -Lo $(OPM) $${download_url}; \
		chmod +x $(OPM); \
	fi

GRPCURL := $(LOCAL_BIN)/grpcurl

$(GRPCURL):
	mkdir -p $(@D)

# gRPCurl Repo: https://github.com/fullstorydev/grpcurl
.PHONY: grpcurl
grpcurl: $(GRPCURL)
	# Checking installation of grpcurl
	@pinned_release="v1.9.3"; \
	if ! $(GRPCURL) --version || [ "$$($(GRPCURL) --version 2>&1 | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)" != "$${pinned_release}" ]; then \
		echo "Installing grpcurl $${pinned_release}"; \
		[ "$(GOOS)" = "darwin" ] && go_os="osx" || go_os=$(GOOS); \
		[ "$(GOARCH)" = "amd64" ] && go_arch="x86_64" || go_arch=$(GOARCH); \
		download_file=grpcurl_$${pinned_release#v}_$${go_os}_$${go_arch}.tar.gz; \
		download_url="https://github.com/fullstorydev/grpcurl/releases/download/$${pinned_release}/$${download_file}"; \
		mkdir -p $${download_file%.tar.gz}; \
		if curl --fail -Lo $${download_file%.tar.gz}/$${download_file} $${download_url}; then \
			tar xvzf $${download_file%.tar.gz}/$${download_file} -C $${download_file%.tar.gz}; \
			mv $${download_file%.tar.gz}/grpcurl $(GRPCURL); \
			chmod +x $(GRPCURL); \
			rm -rf $${download_file%.tar.gz}; \
		else exit 1; fi; \
	fi

# ============================================================================
# Utilities
# ============================================================================

.PHONY: clean
clean:
	-rm -rf bin/
	./scripts/reset-test-environment.sh
