LOCAL_BIN ?= $(PWD)/bin
export PATH := $(LOCAL_BIN):$(PATH)
GOOS := $(shell go env GOOS)
GOARCH := $(shell go env GOARCH)

.PHONY: clean
clean:
	-rm -rf bin/
	./scripts/reset-test-environment.sh

OPM = $(LOCAL_BIN)/opm

$(OPM):
	mkdir -p $(@D)

.PHONY: opm
opm: $(OPM)
	# Checking installation of opm
	@current_release_json=$$(curl -s "https://api.github.com/repos/operator-framework/operator-registry/releases/latest"); \
	current_release=$$(printf '%s\n' "$${current_release_json}" | jq -r '.tag_name'); \
	if ! $(OPM) version || [ "$$($(OPM) version | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)" != "$${current_release}" ]; then \
		echo "Installing opm $${current_release}"; \
		download_url=$$(printf '%s\n' "$${current_release_json}" | jq -r '.assets[] | select(.name == "$(GOOS)-$(GOARCH)-opm").browser_download_url'); \
		curl --fail -Lo $(OPM) $${download_url}; \
		chmod +x $(OPM); \
	fi

.PHONY: validate-catalog validate-catalogs
validate-catalog: opm
	@for catalog in catalog-*/; do \
		echo "Validating $${catalog} ..."; \
		$(OPM) validate $${catalog}; \
	done
validate-catalogs: validate-catalog

VERSION_TAG ?= latest
IMG_REPO ?= quay.io/stolostron
IMAGE_TAG_BASE ?= $(IMG_REPO)/submariner-operator-fbc
IMG ?= $(IMAGE_TAG_BASE):$(VERSION_TAG)

.PHONY: build-image build-images
build-image:
	podman build -t $(IMG) -f catalog.Dockerfile --build-arg INPUT_DIR=$$(find catalog-* -type d -maxdepth 0 | head -1) .
build-images: build-image

.PHONY: build-catalog build-catalogs
build-catalogs: opm
	./build/build.sh
build-catalog: build-catalogs

# ref: https://github.com/operator-framework/operator-registry?tab=readme-ov-file#using-the-catalog-locally
.PHONY: run-image run-images
run-image: build-image
	$(MAKE) stop-image
	podman run -d -p 50051:50051 $(IMG) &
run-images: run-image

.PHONY: stop-image stop-images
stop-image:
	podman stop --filter "ancestor=$(IMG)"
stop-images: stop-image

GRPCURL := $(LOCAL_BIN)/grpcurl

$(GRPCURL):
	mkdir -p $(@D)

# gRPCurl Repo: https://github.com/fullstorydev/grpcurl
.PHONY: grpcurl
grpcurl: $(GRPCURL)
	# Checking installation of grpcurl
	@current_release_json=$$(curl -s "https://api.github.com/repos/fullstorydev/grpcurl/releases/latest"); \
	current_release=$$(printf '%s\n' "$${current_release_json}" | jq -r '.tag_name'); \
	if ! $(GRPCURL) --version || [ "$$($(GRPCURL) --version 2>&1 | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)" != "$${current_release}" ]; then \
		echo "Installing grpcurl $${current_release}"; \
		[ "$(GOOS)" = "darwin" ] && go_os="osx" || go_os=$(GOOS); \
		[ "$(GOARCH)" = "amd64" ] && go_arch="x86_64" || go_arch=$(GOARCH); \
		download_file=grpcurl_$${current_release#v}_$${go_os}_$${go_arch}.tar.gz; \
		mkdir $${download_file%.tar.gz}; \
		download_url=$$(printf '%s\n' "$${current_release_json}" | jq -r '.assets[] | select(.name == "'$${download_file}'").browser_download_url'); \
		if curl --fail -Lo $${download_file%.tar.gz}/$${download_file} $${download_url}; then \
			tar xvzf $${download_file%.tar.gz}/$${download_file} -C $${download_file%.tar.gz}; \
			mv $${download_file%.tar.gz}/grpcurl $(GRPCURL); \
			chmod +x $(GRPCURL); \
			rm -rf $${download_file%.tar.gz}; \
		else exit 1; fi; \
	fi

.PHONY: test-image test-images
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
test-images: test-image

.PHONY: test-script test-scripts
test-scripts: opm
	./test/test.sh
test-script: test-scripts

.PHONY: add-bundle
add-bundle:
	./build/add-bundle.sh $(BUNDLE_IMAGE) $(REPLACES) $(SKIP_RANGE)

.PHONY: validate-markdown md
validate-markdown:
	npx markdownlint-cli2 ".agents/workflows/*.md" "*.md"
md: validate-markdown
