# Submariner Operator FBC

This repository manages File-Based Catalogs (FBC) for the Submariner operator across OpenShift Container Platform (OCP) versions 4.14 through 4.21 using GitOps workflows.

**What is FBC?** Modern declarative YAML format for distributing Kubernetes operators via OLM (Operator Lifecycle Manager). FBCs define operator bundles (versioned packages), channels (upgrade paths), and metadata as files, enabling GitOps workflows and multi-version support unlike legacy index images.

## Table of Contents

**Getting Started:**

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Which Workflow Do I Need?](#which-workflow-do-i-need)

**Reference:**

- [Makefile Targets](#makefile-targets)

**Understanding the Repository:**

- [Repository Structure](#repository-structure)
- [Catalog Generation](#catalog-generation)
- [Extracting Production Catalogs](#extracting-production-catalogs)
- [Testing](#testing)

**Help:**

- [Troubleshooting](#troubleshooting)
- [Glossary](#glossary)

## Prerequisites

**Environment:**
- Konflux cluster access: `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`
- Disconnect from Red Hat VPN (registry.redhat.io blocks corporate VPN)
- Registry authentication: `podman login registry.redhat.io`

**Required Tools:**
- Core: `oc`, `gh`, `git`, `make`, `podman`, `skopeo`
- Text processing: `curl`, `jq`, `yq`, `grep`, `awk`, `sed`
- System utilities: `csplit`, `timeout`, `find`, `cat`, `tar`, `sort` (with --version-sort)

See [workflow docs](.agents/workflows/) for detailed requirements per scenario.

## Quick Start

Add or update Submariner operator bundles:

```bash
# Update existing version with new SHA (most common)
make update-bundle VERSION=0.21.2

# Add first release of new minor version (Y-stream: 0.23)
make update-bundle VERSION=0.23.0

# Skip broken version
make update-bundle VERSION=0.20.3 REPLACE=0.20.2
```

**What this does:** Automatically detects your scenario (UPDATE existing SHA, ADD new version, or REPLACE broken version), updates the catalog template, rebuilds catalogs for OCP 4.14-4.21, and creates a signed-off commit.

**After running:** Review with `git show`, validate with `make validate-catalogs`, then push and create a PR.

See [update-catalog.md](.agents/workflows/update-catalog.md) for detailed workflow documentation.

## Which Workflow Do I Need?

**Choose based on your task:**

1. **Adding or updating Submariner bundles** (most common)
   Use [update-catalog.md](.agents/workflows/update-catalog.md)

2. **Adding support for new OCP version**
   Use [add-ocp-version.md](.agents/workflows/add-ocp-version.md)

> **Note:** The manual URL sync workflow ([update-prod-url.md](.agents/workflows/update-prod-url.md)) is deprecated. The `update-bundle` script handles this automatically.

## Makefile Targets

### Main Workflow

| Target | Description | Usage |
| --- | --- | --- |
| `update-bundle` | Add/update operator bundles with scenario detection | `make update-bundle VERSION=<version>` |

### Catalog Operations

| Target | Description | Usage |
| --- | --- | --- |
| `build-catalogs` | Build catalogs for all OCP versions (4-14 through 4-21) | `make build-catalogs` |
| `validate-catalogs` | Validate catalog structure | `make validate-catalogs` |
| `fetch-catalog` | Extract production catalog | `make fetch-catalog [OCP_VERSION=<version>] [PACKAGE=<name>]` |
| `extract-image` | Extract container image filesystem | `make extract-image IMAGE=<image> [OUTPUT_DIR=<path>]` |

### Container Image Operations

| Target | Description | Usage |
| --- | --- | --- |
| `build-image` | Build OCI catalog image | `make build-image` |
| `run-image` | Build and run catalog image on port 50051 | `make run-image` |
| `test-image` | Test catalog image | `make test-image` |
| `stop-image` | Stop catalog image | `make stop-image` |

### Testing

| Target | Description | Usage |
| --- | --- | --- |
| `test` | Run unit + integration tests (~90s) | `make test` |
| `test-e2e` | Run end-to-end tests (~45s, requires cluster) | `make test-e2e` |

### Linting

| Target | Description | Usage |
| --- | --- | --- |
| `shellcheck` | Lint shell scripts | `make shellcheck` |
| `mdlint` | Lint Markdown files | `make mdlint` |
| `yamllint` | Lint YAML files | `make yamllint` |
| `lint` | Run all linting | `make lint` |
| `ci` | Run catalog validation, linting, and fast tests | `make ci` |

### Tool Installation

| Target | Description | Usage |
| --- | --- | --- |
| `opm` | Install `opm` (Operator Package Manager) v1.56.0 | `make opm` |
| `grpcurl` | Install `grpcurl` v1.9.3 | `make grpcurl` |

### Utilities

| Target | Description | Usage |
| --- | --- | --- |
| `clean` | Clean build/test artifacts and restore from git | `make clean` |

## Repository Structure

```text
submariner-operator-fbc/
├── catalog-template.yaml       # Source template (edit this)
├── catalog-4-14/ ... 4-21/     # Generated (do not edit)
├── drop-versions.json          # OCP version filtering config
├── catalog.Dockerfile          # OCI catalog image build
├── Makefile                    # Build automation
├── bin/                        # Downloaded tools (opm, grpcurl)
├── scripts/
│   ├── update-bundle.sh        # Bundle automation
│   ├── generate-catalog-template.sh
│   ├── render-catalog.sh
│   ├── format-yaml.sh
│   ├── fetch-catalog-containerized.sh
│   ├── image-extract.sh
│   ├── reset-test-environment.sh
│   └── lib/
│       ├── catalog-functions.sh   # FBC functions
│       └── test-helpers.sh        # Test helpers
├── build/
│   └── build.sh                # Catalog generation
├── .agents/workflows/          # Workflow documentation
├── .tekton/                    # CI/CD pipeline definitions
└── test/
    ├── unit/                   # Unit tests
    ├── integration/            # Integration tests
    ├── scripts/                # Build validation tests
    ├── e2e/                    # End-to-end tests
    ├── fixtures/               # Test data
    ├── lib/                    # Shared test infrastructure
    └── test.sh                 # Test orchestrator
```

## Catalog Generation

The `make build-catalogs` command:

1. **Filters** `catalog-template.yaml` per OCP version using `drop-versions.json`
   - Excludes bundles with versions less than or equal to the configured minimum
   - Creates intermediate `catalog-template-4-*.yaml` files
   - Example: OCP 4.19 with minimum "0.19" excludes all 0.19.x versions, includes only 0.20+
2. **Renders** templates with `opm alpha render-template` and splits into individual files
   - OCP ≤ 4.16: Standard rendering
   - OCP ≥ 4.17: Adds metadata migration flag for newer OCP compatibility
   - Uses authenticated local opm for private registries, podman for public
   - Splits output into `catalog-*/bundles/`, `catalog-*/channels/`, `catalog-*/package.yaml`
3. **Sorts** `catalog-template.yaml` entries (package first, then channels and bundles alphabetically)
4. **Converts** bundle URLs in generated catalogs from quay.io to registry.redhat.io
5. **Formats** YAML files
6. **Cleans up** intermediate template files

Validate with `make validate-catalogs`.

## Extracting Production Catalogs

Extract production catalogs from Red Hat's operator index:

```bash
make fetch-catalog OCP_VERSION=4.19 PACKAGE=submariner
```

Output: `submariner-catalog-config-4.19.yaml`

## Testing

Run `make test` for unit and integration tests, or `make test-e2e` for end-to-end validation (requires cluster access).

**Tip:** Skip cluster-dependent tests with `SKIP_AUTH_TESTS=true make test`

## Troubleshooting

### Common Errors

#### VPN Connection Issues

```text
Error: Failed to access registry.redhat.io
Error: x509: certificate signed by unknown authority
```

See [Prerequisites](#prerequisites) - ensure you're disconnected from Red Hat VPN.

#### Authentication Failures

```text
Error: No push-event snapshot found
Error: Unauthorized: authentication required
```

Verify authentication (see [Prerequisites](#prerequisites) for setup):
- Check cluster access: `oc whoami --show-console`
- If expired, re-authenticate to Konflux and registry.redhat.io

#### Bundle Version Mismatch

```text
Error: opm validate fails
Error: Bundle submariner.vX.Y.Z not found in channel
```

- Verify version format: `0.22.1` (not `v0.22.1`)
- Check bundle exists in snapshot: `oc get snapshot $SNAPSHOT -n submariner-tenant -o yaml`
- Rebuild catalogs: `make build-catalogs validate-catalogs`

#### Test Failures (Local Development)

```text
Error: skopeo inspect failed
Error: oc command not found
```

Skip authentication-required tests: `SKIP_AUTH_TESTS=true make test`

#### Catalog Build Errors

```text
Error: SHA mismatch between template and catalogs
Error: Catalog-4-XX validation failed
```

- Verify no manual edits to `catalog-4-*/` directories
- Re-run build process: `make build-catalogs`
- Check template syntax: `yq eval catalog-template.yaml`

### Known Constraints

#### Mirror File Size Limit (4096 bytes)

The `.tekton/images-mirror-set.yaml` file is limited to 4096 bytes (Tekton task result constraint), restricting catalogs to one unreleased Y-stream at a time.

`make update-bundle` automatically handles this by:

- Converting released bundles to registry.redhat.io (no mirrors needed)
- Removing unreleased bundles from other Y-streams with a warning

```text
ℹ️  Removing unreleased bundle from Y-stream 0-23: submariner.v0.23.0
```

No action required - this is expected behavior.

## Glossary

**Core Concepts:**

- **OLM**: Manages operator installation, upgrades, and lifecycle
- **Bundle**: Versioned operator package with manifests and metadata
- **Channel**: Upgrade path for bundles (e.g., `stable-0.22`)
- **skipRange**: OLM metadata allowing direct upgrades (e.g., `>=0.21.0 <0.22.0` lets users skip patch versions)

**Version Notation:**

- `0.X.Y` (semver): Bundle names (e.g., `submariner.v0.22.1`)
- `0-X-TIMESTAMP` (dashed): Snapshot names (e.g., `submariner-0-22-20260326-143000-000`)
- `0-X` (Y-stream): Minor version identifier used in component names (e.g., `submariner-bundle-0-22` for all 0.22.x releases)

**Konflux & Registry:**

- **Konflux**: Red Hat CI/CD platform for operator builds
- **Snapshot**: Konflux build output containing bundle image
- **quay.io**: Temporary workspace registry (pre-release)
- **registry.redhat.io**: Production registry (released bundles)
