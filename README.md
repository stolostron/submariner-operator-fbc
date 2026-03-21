# Submariner Operator FBC

This repository manages File-Based Catalogs (FBC) for the Submariner operator across OCP versions 4-14 through 4-21
using automated GitOps workflows.

**What is FBC?** Modern declarative YAML format for distributing Kubernetes operators via OLM. Unlike legacy index
images, FBCs define operator bundles, channels, and upgrade paths as files, enabling GitOps workflows and
multi-version support.

## Repository Structure

```text
submariner-operator-fbc/
├── catalog-template.yaml       # Source template for all catalogs
├── catalog-4-14/ ... 4-21/     # Generated catalogs (8 OCP versions)
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
    ├── fixtures/               # Test data (catalog templates, snapshots)
    └── test-*.sh               # Legacy integration tests
```

**Key files:**

- `catalog-template.yaml` - Single source of truth for all bundle definitions (edit this, not generated catalogs)
- `drop-versions.json` - Defines minimum Submariner version per OCP version (controls bundle pruning)
- `catalog-4-*/` - Generated FBC directories (DO NOT EDIT manually)

## Which Workflow Do I Need?

**Choose based on your task:**

1. **Adding or updating Submariner bundles** (most common)
   → Use [update-catalog.md](.agents/workflows/update-catalog.md) - Add new versions or rebuild with new image SHAs

2. **Converting staged URLs to production** (after prod release)
   → Use [update-prod-url.md](.agents/workflows/update-prod-url.md) - Update template from quay.io to registry.redhat.io

3. **Adding support for new OCP version** (when Red Hat releases new OpenShift)
   → Use [add-ocp-version.md](.agents/workflows/add-ocp-version.md) - Configure catalog for new OCP version

## Quick Start

**Update catalog with a new bundle:**

```bash
# Most common: Update existing version with new SHA (rebuild after Konflux build)
make update-bundle VERSION=0.23.1

# Add new Y-stream version (first release of 0.24.x)
make update-bundle VERSION=0.24.0

# Skip broken version (release 0.23.2 in place of problematic 0.23.1)
make update-bundle VERSION=0.23.2 REPLACE=0.23.1
```

**Prerequisites:**

- Cluster access: Login to Konflux with `oc` CLI (read-only access sufficient)
- Network: Disconnect from RH VPN (blocks registry.redhat.io)
- Repository: Run from root directory
- Release complete: Submariner bundle released in submariner-release-management

**After automation completes:**

The script creates a signed commit with catalog changes. Review with `git show`, then push and create a PR.
See [`.agents/workflows/update-catalog.md#4-verify-ci-and-merge`](.agents/workflows/update-catalog.md#4-verify-ci-and-merge)
for complete PR/merge workflow.

**Need manual workflow or troubleshooting?** See [`.agents/workflows/update-catalog.md`](.agents/workflows/update-catalog.md)
for detailed step-by-step documentation.

## Catalog Generation

The `make build-catalogs` command generates FBC directories for all 8 supported OCP versions
(4-14 through 4-21):

1. Generates version-specific templates from `catalog-template.yaml` using `drop-versions.json` to
   prune bundles below the minimum supported version
2. Renders templates with `opm` tool (OCP 4.17+ require `--migrate-level` flag) and decomposes into
   file-based catalog structure
3. Replaces dev URLs (`quay.io/redhat-user-workloads/...`) with production URLs
   (`registry.redhat.io/...`)
4. Validates and formats all YAML files

For implementation details, see `build/build.sh` and `scripts/`.

## Catalog Management

The catalog is managed through automated workflows that update the
`catalog-template.yaml` source file and regenerate version-specific catalogs
for all supported OCP versions (4-14 through 4-21).

### Updating the Catalog

**When to update:** After a Submariner bundle release completes (stage or prod) in the
submariner-release-management repository.

Use the `update-bundle` target to add or update operator bundles:

```bash
# UPDATE: Rebuild existing version with new SHA (most common use case)
make update-bundle VERSION=0.23.1

# ADD: Add new Y-stream version with new channel
make update-bundle VERSION=0.24.0

# REPLACE: Skip problematic version in upgrade path
make update-bundle VERSION=0.23.2 REPLACE=0.23.1

# AUTO-CONVERT: Convert quay.io pre-release URLs to registry.redhat.io production URLs
make update-bundle VERSION=0.23.1 AUTO_CONVERT=true

# EXPLICIT SNAPSHOT: Use specific snapshot instead of auto-detection
make update-bundle VERSION=0.23.1 SNAPSHOT=submariner-0-23-xxxxx
```

**What the automation does:**

1. Finds the latest passing snapshot from Konflux cluster (or uses provided
   snapshot)
2. Detects scenario automatically (UPDATE/ADD/REPLACE) based on catalog state
3. Updates `catalog-template.yaml` with correct bundle and channel entries
4. Rebuilds all 8 OCP-specific catalogs (4-14 through 4-21)
5. Validates catalogs with `opm validate`
6. Creates a signed commit with scenario metadata

**After running the automation:**

- Review the commit: `git show`
- Push changes: `git push origin <branch>`
- Create PR: `gh pr create`
- Wait for CI validation (~5-15 min)
- Merge when passing

See [`.agents/workflows/update-catalog.md`](.agents/workflows/update-catalog.md)
for detailed workflow documentation, troubleshooting, and manual workflows for
edge cases.

## Testing

Comprehensive test coverage with **52 tests** organized into unit and integration suites:

- `make test-scripts` - All tests (unit tests first for fast feedback, then integration tests)
- `make validate-catalogs` - Validates generated catalogs with `opm`
- `make test-images` - Tests catalog image functionality

**Test organization:**

- `test/unit/` - 38 unit tests across 5 files (SHA extraction, version validation, bundle/channel queries, scenario detection)
- `test/integration/` - 14 integration tests across 3 workflow files (ADD/UPDATE/REPLACE scenarios)
- `test/fixtures/` - Test data (catalog templates, snapshot JSON)
- `test/test-*.sh` - Legacy integration tests (build, format validation)

**Test libraries:**

- `scripts/lib/catalog-functions.sh` - Reusable FBC manipulation functions
- `scripts/lib/test-helpers.sh` - Test assertion framework (`assert_equals`, `assert_exit_code`, fixtures)

All tests run automatically on every push/PR via GitHub Actions. Use `SKIP_AUTH_TESTS=true make test-scripts` for local testing without authentication.

## Makefile Targets

### Primary Targets

| Target | Description | Usage |
| --- | --- | --- |
| `update-bundle` | Automated workflow to add/update operator bundles with scenario detection | `make update-bundle VERSION=0.23.1` |
| `build-catalogs` | Builds File-Based Catalogs for all 8 supported OCP versions (4-14 through 4-21) | `make build-catalogs` |
| `validate-catalogs` | Validates all generated catalogs using `opm validate` | `make validate-catalogs` |
| `test-scripts` | Runs the test suite (build, generate-template, format tests) | `make test-scripts` |
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

- **Bundle Version Mismatch:** Some upstream bundles have image labels that don't match internal CSV
  versions (e.g., `v0.21.0-rc0` vs `v0.21.0`), causing `opm validate` failures.

- **Channel Naming:** Need to unify on `alpha` (upstream `bundle.Dockerfile`) vs `stable`
  (downstream `render_vars.in` and `submariner-catalog-config-4.19.yaml`) channel naming convention.
