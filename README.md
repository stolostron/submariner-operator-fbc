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

To add a new operator bundle to the catalog, use the `scripts/add-bundle.sh` script. This script takes the bundle image tag as an argument and will add it to the `catalog-template.yaml`.

```bash
./scripts/add-bundle.sh <bundle_image_tag>
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
| `build-catalogs` | Builds the catalogs for all supported OpenShift versions. |
| `validate-catalogs` | Validates the generated catalogs using `opm`. |
| `build-images` | Builds the catalog image. |
| `run-images` | Runs the catalog image in the background. |
| `test-images` | Builds, runs, and tests the catalog image. |
| `stop-images` | Stops the running catalog image. |
| `test-scripts` | Runs the main test script at `test/test.sh`. |
| `clean` | Removes the `bin/` directory. |
| `opm` | Installs the `opm` binary. |
