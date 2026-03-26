# Submariner Operator FBC

This repository manages File-Based Catalogs (FBC) for the Submariner operator across OCP versions 4-14 through 4-21
using automated GitOps workflows.

**What is FBC?** Modern declarative YAML format for distributing Kubernetes operators via OLM. Unlike legacy index
images, FBCs define operator bundles, channels, and upgrade paths as files, enabling GitOps workflows and
multi-version support.

## Table of Contents

**Getting Started:**

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

## Quick Start

```bash
# Update existing version with new SHA (most common)
make update-bundle VERSION=0.22.1

# Add first release of new Y-stream
make update-bundle VERSION=0.23.0

# Skip broken version
make update-bundle VERSION=0.22.2 REPLACE=0.22.1
```

Creates a signed commit - review with `git show`, then push and create a PR.
See [update-catalog.md](.agents/workflows/update-catalog.md) for details.

## Which Workflow Do I Need?

**Choose based on your task:**

1. **Adding or updating Submariner bundles** (most common)
   Use [update-catalog.md](.agents/workflows/update-catalog.md)

2. **Converting staged URLs to production** (after prod release)
   Use [update-prod-url.md](.agents/workflows/update-prod-url.md)

3. **Adding support for new OCP version** (when Red Hat releases new OpenShift)
   Use [add-ocp-version.md](.agents/workflows/add-ocp-version.md)

## Makefile Targets

### Main Workflow

| Target | Description | Usage |
| --- | --- | --- |
| `update-bundle` | Add/update operator bundles with scenario detection | `make update-bundle VERSION=0.23.1` |

### Catalog Operations

| Target | Description | Usage |
| --- | --- | --- |
| `build-catalogs` | Build catalogs for all OCP versions (4-14 through 4-21) | `make build-catalogs` |
| `validate-catalogs` | Validate catalog structure and bundle references | `make validate-catalogs` |
| `fetch-catalog` | Extract production catalog | `make fetch-catalog [OCP_VERSION=4.21] [PACKAGE=submariner]` |
| `extract-image` | Extract container image filesystem | `make extract-image IMAGE=<image> [OUTPUT_DIR=<path>]` |

### Container Image Operations

| Target | Description | Usage |
| --- | --- | --- |
| `build-image` | Build OCI catalog image | `make build-image` |
| `run-image` | Run catalog image on port 50051 | `make run-image` |
| `test-image` | Test catalog image | `make test-image` |
| `stop-image` | Stop catalog image | `make stop-image` |

### Test Targets

| Target | Description | Usage |
| --- | --- | --- |
| `test` | Unit + integration tests (~15s) - runs in CI | `make test` |
| `test-e2e` | End-to-end tests (~45s) - requires cluster access | `make test-e2e` |

### Linting

| Target | Description | Usage |
| --- | --- | --- |
| `shellcheck` | Lint shell scripts | `make shellcheck` |
| `mdlint` | Lint Markdown files | `make mdlint` |
| `yamllint` | Lint YAML files | `make yamllint` |
| `lint` | Run all linting | `make lint` |
| `ci` | Run catalog validation, linting, and tests | `make ci` |

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
├── scripts/
│   ├── update-bundle.sh        # Bundle automation
│   ├── generate-catalog-template.sh
│   ├── render-catalog.sh
│   ├── format-yaml.sh
│   └── lib/
│       ├── catalog-functions.sh   # FBC functions
│       └── test-helpers.sh        # Test helpers
├── build/
│   └── build.sh                # Catalog generation
├── .agents/workflows/          # Workflow documentation
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

1. Filters `catalog-template.yaml` per OCP version using `drop-versions.json`
2. Renders templates with `opm`, decomposes to file-based structure
3. Converts released bundle URLs from quay.io to registry.redhat.io
4. Validates and formats YAML

## Extracting Production Catalogs

Extract current production catalogs from Red Hat's operator index:

```bash
make fetch-catalog OCP_VERSION=4.19 PACKAGE=submariner
```

Output: `submariner-catalog-config-4.19.yaml`

## Testing

- `make test` - Unit + integration tests (~15s)
- `make test-e2e` - End-to-end tests (~45s, requires cluster)
- `make validate-catalogs` - Catalog validation

Skip cluster-dependent tests: `SKIP_AUTH_TESTS=true make test`

## Troubleshooting

### Common Errors

#### VPN Connection Issues

```text
Error: Failed to access registry.redhat.io
Error: x509: certificate signed by unknown authority
```

Disconnect from Red Hat VPN. The registry.redhat.io service may have connectivity issues when using corporate VPN.

#### Authentication Failures

```text
Error: No push-event snapshot found
Error: Unauthorized: authentication required
```

- Verify Konflux cluster login: `oc whoami --show-console`
- Re-authenticate if session expired: `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`
- For registry.redhat.io: `podman login registry.redhat.io`

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

The `.tekton/images-mirror-set.yaml` file is limited to 4096 bytes (Tekton task result constraint), allowing only one
unreleased Y-stream at a time. The `make update-bundle` script automatically handles this by:

- Converting released bundles to registry.redhat.io (no mirrors needed)
- Removing unreleased bundles from other Y-streams with a warning

```text
⚠ Removing unreleased bundle submariner.v0.23.0 from Y-stream 0-23
  Reason: Mirror file size limit (4KB) allows only one unreleased Y-stream
```

No action required - this is expected behavior.

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
