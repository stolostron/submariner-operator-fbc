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
make update-bundle VERSION=0.21.2

# Add first release of new Y-stream
make update-bundle VERSION=0.23.0

# Skip broken version
make update-bundle VERSION=0.20.3 REPLACE=0.20.2
```

This creates a signed-off commit - review with `git show`, then push and create a PR.
See [update-catalog.md](.agents/workflows/update-catalog.md) for details.

## Which Workflow Do I Need?

**Choose based on your task:**

1. **Adding or updating Submariner bundles** (most common)
   Use [update-catalog.md](.agents/workflows/update-catalog.md)
   Automatically handles URL conversion from staging to production.

2. **Syncing production URLs manually** (edge cases only, usually automatic)
   Use [update-prod-url.md](.agents/workflows/update-prod-url.md)
   Manual workflow for batch URL conversions. Deprecated - use workflow #1 for normal cases.

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
| `validate-catalogs` | Validate catalog structure | `make validate-catalogs` |
| `fetch-catalog` | Extract production catalog | `make fetch-catalog [OCP_VERSION=4.21] [PACKAGE=submariner]` |
| `extract-image` | Extract container image filesystem | `make extract-image IMAGE=<image> [OUTPUT_DIR=<path>]` |

### Container Image Operations

| Target | Description | Usage |
| --- | --- | --- |
| `build-image` | Build OCI catalog image | `make build-image` |
| `run-image` | Build and run catalog image on port 50051 | `make run-image` |
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

1. **Filters** `catalog-template.yaml` per OCP version using `drop-versions.json` with exclusive semantics (>)
   - Creates intermediate `catalog-template-4-*.yaml` files
   - Example: OCP 4.19 with minimum "0.19" includes only versions > 0.19 (i.e., 0.20+), excludes 0.19 itself
2. **Renders** templates with `opm alpha render-template`, decomposes to file-based structure
   - OCP ≤ 4.16: Standard rendering
   - OCP ≥ 4.17: Adds `--migrate-level=bundle-object-to-csv-metadata` for compatibility
   - Uses local opm (with auth) for registry.redhat.io bundles, podman for quay.io
   - Decomposes to `catalog-*/bundles/`, `catalog-*/channels/`, `catalog-*/package.yaml` using csplit
3. **Sorts** `catalog-template.yaml` entries (package first, then channels alphabetically, then bundles alphabetically)
4. **Converts** bundle URLs in generated catalogs from quay.io to registry.redhat.io
5. **Formats** YAML files
6. **Cleans up** intermediate template files

Run `make validate-catalogs` separately to validate.

## Extracting Production Catalogs

Extract production catalogs from Red Hat's operator index:

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

Disconnect from Red Hat VPN. The registry.redhat.io service may have connectivity issues with corporate VPN.

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
unreleased Y-stream at a time. `make update-bundle` automatically handles this by:

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
- **Channel**: Upgrade path grouping bundles (e.g., `stable-0.22`)
- **skipRange**: OLM metadata controlling upgrade paths

**Version Notation:**

- `0.X.Y` (semver): Bundle names (e.g., `submariner.v0.22.1`)
- `0-X-TIMESTAMP` (dashed): Snapshot names (e.g., `submariner-0-22-20260326-143000-000`)
- `0-X` (Y-stream): Component names (e.g., `submariner-bundle-0-22`)

**Konflux & Registry:**

- **Konflux**: Red Hat CI/CD platform for operator builds
- **Snapshot**: Konflux build output containing bundle image
- **quay.io**: Temporary workspace registry (pre-release)
- **registry.redhat.io**: Production registry (released bundles)
