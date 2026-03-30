# Submariner Operator FBC

Automated catalog distribution for the Submariner multi-cluster networking operator.

## What is This?

This repository maintains file-based catalogs that make **Submariner** installable via OpenShift's Operator Lifecycle Manager.
It automates release updates, multi-version catalog generation, and production URL management across OCP 4-14 through 4-21.

**Submariner** enables secure networking between pods and services across multiple Kubernetes clusters.

**File-Based Catalog (FBC)** is OLM's declarative YAML format for distributing operators via version control.

## Key Features

- **Scenario detection**: Automatically handles UPDATE, ADD, and REPLACE workflows
- **Multi-version support**: Single template maintains 8 OCP catalogs (4-14 through 4-21)
- **GitOps workflow**: Git-tracked changes with CI validation and Konflux builds
- **Production URL conversion**: Converts pre-release quay.io URLs to registry.redhat.io
- **Comprehensive validation**: OPM, linting, and integration tests

## Prerequisites

**Authentication:**

- Konflux: `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`
- registry.redhat.io: `podman login` (requires Red Hat subscription)
- GitHub: `gh auth login`
- Git: set `user.name` and `user.email`

**Required tools:** `oc`, `gh`, `git`, `make`, `podman`, `skopeo`, `bash`, `opm` v1.56.0 (`make opm`)

**Supporting utilities:** `curl`, `jq`, `yq`, and standard POSIX utilities

**CI environment:** `yamllint`, `shellcheck`, `npm`

**⚠️ VPN:** Disconnect Red Hat VPN before running `make build-catalogs`, `make update-bundle`, or `podman login registry.redhat.io`
(the VPN blocks registry.redhat.io)

**Verification:**

```bash
make opm && command -v bash jq yq podman skopeo >/dev/null && \
  oc whoami && gh auth status && \
  git config user.name && git config user.email
```

## Quick Start

```bash
# Create feature branch (script commits to current branch)
git checkout -b 0.22.1-stage  # Format: <version>-stage or <version>-prod

# Run update-bundle (auto-detects UPDATE/ADD/REPLACE scenarios)
make update-bundle VERSION=0.22.1                          # Most common
make update-bundle VERSION=0.22.1 SNAPSHOT=submariner-0-22-20260326-225632-000  # Explicit snapshot
```

**After the script completes** (creates a signed-off commit on your branch):

1. Review: `git show`
2. Push: `git push origin 0.22.1-stage`
3. Create PR: `gh pr create --title "Update catalog with bundle v0.22.1" --body "Snapshot: submariner-0-22-20260326-225632-000"`
4. Wait for CI (~5-15 min): `gh pr checks`
5. Merge: `gh pr merge --squash`
6. Post-merge: Verify snapshots (see [section 5](.agents/workflows/update-catalog.md#5-verify-konflux-snapshots), ~15-30 min)

## Which Workflow Do I Need?

**Submariner bundle released (0.X.Y)?** → [update-catalog.md](.agents/workflows/update-catalog.md)

**Red Hat released new OCP version (4-X)?** → [add-ocp-version.md](.agents/workflows/add-ocp-version.md)

## Makefile Targets

### Workflows

| Target | Description |
| --- | --- |
| `update-bundle` | Add or update bundles (auto-detects scenario) |
| `build-catalogs` | Build catalogs for all OCP versions |
| `validate-catalogs` | Validate catalog structure with opm |
| `fetch-catalog` | Extract production catalog from registry.redhat.io (`OCP_VERSION=<ver> PACKAGE=<pkg>`) |

### Testing & Quality

| Target | Description |
| --- | --- |
| `test` | Run unit + integration tests (~90s) |
| `test-e2e` | End-to-end tests (~45s, requires cluster) |
| `shellcheck` | Lint shell scripts |
| `mdlint` | Lint markdown files |
| `yamllint` | Lint YAML files |
| `lint` | Run all linting (shell + Markdown + YAML) |
| `ci` | Full validation: catalogs + linting + tests |

### Images & Tools

| Target | Description |
| --- | --- |
| `build-image` | Build catalog image |
| `run-image` | Build and run image on port 50051 |
| `test-image` | Build, run, and test image |
| `stop-image` | Stop running image |
| `extract-image` | Extract image to filesystem (`IMAGE=<img> [OUTPUT_DIR=<dir>]`) |
| `opm` | Ensure opm v1.56.0 is installed |
| `grpcurl` | Ensure grpcurl v1.9.3 is installed |
| `clean` | Clean build/test artifacts and restore from git |

## Repository Structure

- **Template:** Editable `catalog-template.yaml` auto-generates read-only `catalog-4-14/` through `catalog-4-21/`
- **Scripts:** `scripts/update-bundle.sh` (workflow automation), `scripts/render-catalog.sh` (catalog builder)
- **Config:** `drop-versions.json` (OCP version mappings), `.tekton/` (Konflux pipelines for 4-16+)

**Catalog generation:** `make build-catalogs` filters the template per OCP version, renders via `opm alpha render-template`,
converts quay.io URLs to registry.redhat.io, and formats YAML.

## Troubleshooting

**VPN blocks `registry.redhat.io`** → Disconnect Red Hat VPN

**"No push-event snapshot found"** → Wait for Konflux build (`oc get snapshot $SNAPSHOT -n submariner-tenant`) or use explicit:
`make update-bundle VERSION=0.22.1 SNAPSHOT=submariner-0-22-20260326-225632-000`

**"Cannot replace - version not found"** → `REPLACE=` must be a broken bundle in the catalog; `VERSION=` is the new bundle. Check `catalog-template.yaml`.

**"Invalid version format"** → VERSION must be X.Y.Z format (e.g., 0.22.1, not v0.22.1)

**"Template SHA ≠ catalogs"** → Re-run `make build-catalogs`

**OPM validation fails** → Run `make validate-catalogs` for details

**Not logged into cluster** → Run `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`

**Snapshot tests failed** → Wait for tests to pass or check status: `oc get snapshot $SNAPSHOT -n submariner-tenant -o jsonpath='{.metadata.annotations["test.appstudio.openshift.io/status"]}'`

## Glossary

- **Bundle**: Versioned operator package containing metadata, CRDs, and deployment manifests
- **Channel**: OLM upgrade path defining bundle sequence (e.g., `stable-0.22`)
- **FBC (File-Based Catalog)**: Declarative YAML format for distributing Kubernetes operators via OLM
- **GitOps**: Deployment approach using Git as single source of truth for declarative infrastructure
- **Konflux**: Red Hat's CI/CD build platform for containerized applications
- **Mirror**: Image mirror configuration allowing unreleased quay.io workspace images to be accessed via registry.redhat.io during testing (ImageDigestMirrorSet)
- **OCP**: OpenShift Container Platform (versions 4-14 through 4-21; Konflux pipelines for 4-16+)
- **OLM (Operator Lifecycle Manager)**: Kubernetes component managing operator installation and upgrades
- **OPM (Operator Package Manager)**: CLI tool for building and validating OLM catalogs (v1.56.0)
- **Scenario**: UPDATE (rebuild with new SHA), ADD (new version), REPLACE (skip broken version)
- **Snapshot**: Konflux build output artifact containing component images
- **Template**: Source file (`catalog-template.yaml`) that generates all OCP-specific catalogs
- **Version notation**:
  - Bundles: `0.X.Y` format (e.g., `submariner.v0.22.1`)
  - Snapshots: `submariner-0-X-YYYYMMDD-HHMMSS-NNN` format (e.g., `submariner-0-22-20260326-225632-000`)
  - Y-stream: `0-X` format representing minor version family (e.g., `0-22` for all v0.22.x releases)
