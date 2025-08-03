# Submariner Operator FBC

This repository manages the File-Based Catalog (FBC) for the `submariner` operator.

## Overview

This repository contains the necessary templates, scripts, and configurations to generate and manage the Submariner operator catalog for various OpenShift versions.

## Catalog Generation

The primary script for building the catalogs is `build/build.sh`, which is invoked by the `make build-catalogs` command. This script orchestrates a series of helper scripts to perform the following steps:

1.  **Clean Previous Artifacts:** Before starting the build, any existing `catalog-*` directories from previous runs are removed to ensure a clean build environment.
2.  **Generate Version-Specific Templates:** The `scripts/generate-catalog-template.sh` script takes the main `catalog-template.yaml` as a base. For each supported OCP version defined in `drop-versions.json` (where keys are OCP versions and values are the minimum supported Submariner versions), it creates a version-specific template (e.g., `catalog-template-4-19.yaml`). It then prunes (removes) older bundles and channels from each of these templates according to the versions specified in `drop-versions.json`. This pruning also includes removing the `replaces` field from channels that end up with only one bundle.
3.  **Render and Decompose Catalogs:** The `scripts/render-catalog-containerized.sh` script processes each of the version-specific templates (e.g., `catalog-template-4-19.yaml`) generated in the previous step. For each template, it first uses the `opm` tool (run via a container) to render it into a temporary, monolithic `catalog-4-19.yaml` file. Note that OCP versions >= 4.17 require an additional `--migrate-level` flag during rendering for compatibility. It then immediately decomposes this monolithic file, splitting it into a standard file-based catalog structure (directories for bundles, channels, and the package file) inside the `catalog-4-19/` directory. The temporary monolithic file is deleted upon completion.
4.  **Sort Catalog Entries:** The main `catalog-template.yaml` file's entries are sorted for consistent ordering.
5.  **Replace Image URLs:** Development image URLs (e.g., `quay.io/redhat-user-workloads/...`) are replaced with production Red Hat URLs (e.g., `registry.redhat.io/...`) to prepare the catalog for production environments.
6.  **Format:** The `scripts/format-yaml.sh` script ensures all YAML files are consistently formatted using `yq`.

## Catalog Management

This repository provides scripts to manage the catalog content incrementally. The `catalog-template.yaml` file is the source of truth for the catalog, and the scripts modify it directly.

### Adding a Bundle

To add a new operator bundle to the catalog, use the `make add-bundle` target. This target takes the `BUNDLE_IMAGE` variable as an argument and will add the specified bundle to the `catalog-template.yaml`.

```bash
make add-bundle BUNDLE_IMAGE=quay.io/my-bundle:latest
```

### Fetching a Catalog for Reference

To fetch the Submariner operator catalog from a specific OpenShift version for reference, use the `scripts/fetch-catalog-containerized.sh` script. This script takes the OpenShift version and the package name as arguments.

```bash
./scripts/fetch-catalog-containerized.sh 4.19 submariner
```

This will produce a file like `submariner-catalog-config-4.19.yaml` which you can use as a reference for the required fields when adding a new bundle.

## Testing

The repository includes a comprehensive set of tests and GitHub Actions to ensure the integrity of the catalog and the functionality of the management scripts.

The following `make` targets are available for testing:

*   `make test-scripts`: Runs the main test script at `test/test.sh`, which executes a series of tests for the catalog management scripts.
*   `make validate-catalog`: Validates the generated catalogs using `opm` to ensure they are well-formed and all references are correct.
*   `make test-image`: Builds, runs, and tests the catalog image. This includes verifying that the image can be served correctly and that the package list is accurate.

These tests are automatically executed on every push and pull request via GitHub Actions.

## Makefile Targets

The following `make` targets are available for use:

| Target | Description |
| --- | --- |
| `build-catalogs` | Builds the File-Based Catalogs (FBC) for all supported OpenShift versions. This target orchestrates the entire catalog generation process as described in the "Catalog Generation" section. |
| `validate-catalogs` | Validates the generated File-Based Catalogs (FBC) using the `opm validate` command. This command performs static analysis and linting of the catalog's declarative configuration files (packages, channels, and bundles) to ensure they are well-formed, adhere to Operator Framework specifications, and have correct references. |
| `build-images` | Builds the OCI (Open Container Initiative) image for the generated catalog. This image can then be used to serve the catalog. |
| `run-images` | Runs the built catalog OCI image in the background, exposing it on a local port (e.g., 50051) for testing and interaction. |
| `test-images` | Performs a comprehensive test of the built catalog OCI image. This includes running the image, verifying its availability, and validating the package list it serves. |
| `stop-images` | Stops any running catalog OCI image instances. |
| `test-scripts` | Executes the main test script (`test/test.sh`), which runs a suite of tests for the catalog management scripts and generated content. |
| `clean` | Removes generated build artifacts and temporary files, including the `bin/` directory and `catalog-template-4-*.yaml` and `catalog-4-*.yaml` files. |
| `opm` | Installs the `opm` (Operator Package Manager) binary, a command-line tool used for building, managing, and serving OLM catalogs. |

## TODOs

*   **Fix Bundle Version Inconsistency:** There is a known bug in some upstream bundles where the version in the image label (e.g., `v0.21.0-rc0`) does not match the version in the internal CSV metadata (e.g., `v0.21.0`). This causes the `opm validate` command to fail. A failing test case that demonstrates this issue can be found at `test/broken-test-add-bundles-from-file.sh`. This test should be moved out of the `broken-` directory and into the main test suite once the upstream bundle is fixed.

*   **Channel Naming Convention:** We need to clarify the correct channel naming convention for the Submariner operator.
    *   The `submariner-catalog-config-4.19.yaml` from the index container and the current downstream bundle both use `stable`.
        ```
        submariner-catalog-config-4.19.yaml:
        entries:
        - defaultChannel: stable-0.20
        ```
        ```
        distgit/containers/submariner-operator-bundle/render_vars.in:
        export BUNDLE_DEFAULT_CHANNEL="stable-${CI_X_VERSION}.${CI_Y_VERSION}"
        export BUNDLE_CHANNELS="stable-${CI_X_VERSION}.${CI_Y_VERSION}"
        ```
    *   However, the upstream bundle uses `alpha`.
        ```
        bundle.Dockerfile.konflux:
        LABEL operators.operatorframework.io.bundle.channel.default.v1=alpha-0.21
        ```
        ```
        bundle.Dockerfile:
        LABEL operators.operatorframework.io.bundle.channels.v1=alpha-0.21
        LABEL operators.operatorframework.io.bundle.channel.default.v1=alpha-0.21
        ```
    We need to determine which channel (`alpha` or `stable`) should be used consistently.
