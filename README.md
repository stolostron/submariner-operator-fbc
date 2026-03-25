# Submariner Operator FBC

This repository manages File-Based Catalogs (FBC) for the Submariner operator across OCP versions 4-14 through 4-21
using automated GitOps workflows.

**What is FBC?** Modern declarative YAML format for distributing Kubernetes operators via OLM. Unlike legacy index
images, FBCs define operator bundles, channels, and upgrade paths as files, enabling GitOps workflows and
multi-version support.

## Glossary

**Core Concepts:**

- **OLM**: Manages operator installation, upgrades, and lifecycle
- **Bundle**: Versioned operator package with manifests and metadata
- **Channel**: Upgrade path grouping bundles (e.g., `stable-0.22`)
- **skipRange**: OLM metadata controlling upgrade paths

**Version Notation:**

- `0.X.Y` (semver): Bundle names (e.g., `submariner.v0.22.1`)
- `0-X-Y` (dashed): URLs and snapshots (e.g., `submariner-0-22-1`)
- `0-X` (Y-stream): Component names (e.g., `submariner-bundle-0-22`)

**Konflux & Registry:**

- **Konflux**: Red Hat CI/CD platform for operator builds
- **Snapshot**: Konflux build output containing bundle image
- **quay.io**: Temporary workspace registry (pre-release)
- **registry.redhat.io**: Production registry (released bundles)

## Repository Structure

```text
submariner-operator-fbc/
├── catalog-template.yaml       # Source template for all catalogs (EDIT THIS, not generated catalogs)
├── catalog-4-14/ ... 4-21/     # Generated catalogs (DO NOT EDIT - rebuilt from template)
├── scripts/
│   ├── update-bundle.sh        # Main automation for bundle updates
│   ├── generate-catalog-template.sh
│   ├── render-catalog.sh
│   ├── format-yaml.sh
│   └── lib/
│       ├── catalog-functions.sh   # Pure functions for FBC manipulation
│       └── test-helpers.sh        # Test assertion helpers
├── build/
│   └── build.sh                # Orchestrates catalog generation
├── .agents/workflows/          # Detailed workflow documentation
└── test/
    ├── unit/                   # Unit tests (pure function testing)
    ├── integration/            # Integration tests (workflow scenarios)
    ├── scripts/                # Build validation tests (catalog generation, template rendering)
    ├── e2e/                    # End-to-end tests (real Konflux cluster, real registries)
    ├── fixtures/               # Test data (catalog templates, snapshots)
    ├── lib/                    # Shared test infrastructure (mock commands, test constants)
    └── test.sh                 # Test orchestrator (runs all tests)
```

## Which Workflow Do I Need?

**Choose based on your task:**

1. **Adding or updating Submariner bundles** (most common)
   → Use [update-catalog.md](.agents/workflows/update-catalog.md) - Add new versions or rebuild with new image SHAs

2. **Converting staged URLs to production** (after prod release)
   → Use [update-prod-url.md](.agents/workflows/update-prod-url.md) - Update template from quay.io to registry.redhat.io

3. **Adding support for new OCP version** (when Red Hat releases new OpenShift)
   → Use [add-ocp-version.md](.agents/workflows/add-ocp-version.md) - Configure catalog for new OCP version

## Quick Start

```bash
# Update existing version with new SHA (most common)
make update-bundle VERSION=0.22.1

# Add first release of new Y-stream
make update-bundle VERSION=0.23.0

# Skip broken version
make update-bundle VERSION=0.22.2 REPLACE=0.22.1
```

**Prerequisites:** Konflux access (`oc login`), `gh` CLI, off VPN, release completed in submariner-release-management

**After:** Script creates signed commit. Review with `git show`, push, create PR.
See [update-catalog.md](.agents/workflows/update-catalog.md) for details.

## Catalog Generation

The `make build-catalogs` command:

1. Filters `catalog-template.yaml` per OCP version using `drop-versions.json`
2. Renders templates with `opm` (4.17+ use `--migrate-level` flag), decomposes to file-based structure
3. Converts quay.io URLs to registry.redhat.io
4. Validates and formats YAML

See `build/build.sh` for implementation.

## Testing

Comprehensive test coverage organized into three levels:

- `make test-scripts` - Fast tests (unit + integration, ~6-7s) - **runs in CI**
- `make test-e2e` - End-to-end tests (real cluster/network, ~5-15min) - **manual only**
- `make validate-catalogs` - Validates generated catalogs with `opm`
- `make test-images` - Tests catalog image functionality

**Test organization:**

- `test/unit/` - Pure function tests (~2s, runs in CI). 4 suites: audit-bundle-urls, catalog-queries, convert-released-bundles, format-validators
- `test/integration/` + `test/scripts/` - Workflow scenarios (~4-5s, runs in CI). ADD/UPDATE/REPLACE workflows with mocked external deps
- `test/e2e/` - Real cluster/registry tests (~5-15min, manual only). Requires: `oc login`, `podman login registry.redhat.io`

Use `SKIP_AUTH_TESTS=true make test-scripts` for local testing without cluster access.

## Makefile Targets

### Primary Targets

| Target | Description | Usage |
| --- | --- | --- |
| `update-bundle` | Automated workflow to add/update operator bundles with scenario detection | `make update-bundle VERSION=0.23.1` |
| `build-catalogs` | Builds File-Based Catalogs for all 8 supported OCP versions (4-14 through 4-21) | `make build-catalogs` |
| `validate-catalogs` | Validates FBC structure and bundle references using `opm validate` | `make validate-catalogs` |
| `test-scripts` | Runs the test suite (56 assertions across unit, integration, and build validation tests) | `make test-scripts` |
| `clean` | Removes build artifacts and temporary files | `make clean` |

### Container Image Targets

| Target | Description |
| --- | --- |
| `build-images` | Builds the OCI image for the generated catalog |
| `run-images` | Runs the catalog OCI image in the background on port 50051 |
| `test-images` | Tests the running catalog image (availability and package list) |
| `stop-images` | Stops any running catalog OCI image instances |

### Development Targets

| Target | Description |
| --- | --- |
| `opm` | Installs the `opm` (Operator Package Manager) binary v1.56.0 |
| `grpcurl` | Installs the `grpcurl` tool v1.9.3 for testing |
| `validate-markdown` | Validates all Markdown documentation files |

## Known Issues

- **Mirror File Size Limit:** The `.tekton/images-mirror-set.yaml` file is limited to 4096 bytes due to
  Tekton task result constraints. To stay within this limit, **only one unreleased Y-stream** can exist
  in the mirror file at a time. When adding a bundle from a new Y-stream (e.g., 0-23), the script
  automatically REPLACES the previous Y-stream (e.g., 0-22) in the mirrors. Unreleased bundles from
  the old Y-stream must be either released to registry.redhat.io, removed from the catalog, or rebuilt
  with the new Y-stream. This is enforced by the `ensure_mirror_ystream()` function in
  `scripts/update-bundle.sh`.
