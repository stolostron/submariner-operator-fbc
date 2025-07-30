# Submariner Operator FBC

This repository manages the File-Based Catalog (FBC) for the `submariner` operator.

## Overview

This repository contains the necessary templates, scripts, and configurations to generate and manage the Submariner operator catalog for various OpenShift versions.

## Catalog Generation

The primary script for building the catalogs is `build/build.sh`. This script orchestrates a series of helper scripts to perform the following steps:

1.  **Generate Version-Specific Templates:** The `scripts/generate-catalog-template.sh` script takes the main `catalog-template.yaml` as a base. For each supported OCP version defined in `drop-versions.json`, it creates a version-specific template (e.g., `catalog-template-4-19.yaml`). It then prunes (removes) older bundles and channels from each of these templates according to the versions specified in `drop-versions.json`.
2.  **Render and Decompose Catalogs:** The `scripts/render-catalog-containerized.sh` script processes each of the version-specific templates (e.g., `catalog-template-4-19.yaml`) generated in the previous step. For each template, it first uses `opm` to render it into a temporary, monolithic `catalog-4-19.yaml` file. It then immediately decomposes this monolithic file, splitting it into a standard file-based catalog structure inside the `catalog-4-19/` directory. The temporary monolithic file is deleted upon completion. The temporary monolithic file is deleted upon completion.
3.  **Format:** The `scripts/format-yaml.sh` script ensures all YAML files are consistently formatted using `yq`.

To build the catalogs, simply run:

```bash
make build-catalogs
```

## Catalog Management

This repository provides scripts to manage the catalog content:

*   **Adding a Bundle:** To add a new operator bundle to the catalog, use the `scripts/add-bundle-to-template.sh` script. This script takes the catalog template path, bundle image, bundle name, bundle version, and channels as arguments.

*   **Removing a Bundle:** To remove an existing operator bundle from the catalog, use the `scripts/remove-bundle.sh` script. This script takes the catalog template path and the bundle version to remove as arguments.

*   **Fetching a Catalog:** To fetch the Submariner operator catalog from a specific OpenShift version, use the `scripts/fetch-catalog-containerized.sh` script. This script takes the OpenShift version and the package name as arguments.

## Testing

The repository includes a comprehensive set of tests and GitHub Actions to ensure the integrity of the catalog and the functionality of the management scripts.

The following `make` targets are available for testing:

*   `make test-scripts`: Runs the main test script at `test/test.sh`.
*   `make validate-catalog`: Validates the generated catalogs using `opm`.
*   `make test-image`: Builds, runs, and tests the catalog image.

These tests are automatically executed on every push and pull request via GitHub Actions.
