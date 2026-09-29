# Submariner Operator FBC

Automated catalog distribution for the Submariner multi-cluster networking operator.

## What is This?

This repository maintains file-based catalogs that make Submariner installable via OpenShift's Operator Lifecycle Manager.
It automates release updates, multi-version catalog generation, and production URL management for the OCP versions configured in `drop-versions.json`.

**Submariner** enables secure networking between pods and services across multiple Kubernetes clusters.

**File-Based Catalog (FBC)** is OLM's declarative YAML format for distributing operators via version control.

## Quick Start

```bash
# Run update-bundle (auto-detects UPDATE/ADD/REPLACE scenarios)
make update-bundle VERSION=0.22.1                                               # Most common
make update-bundle VERSION=0.22.1 SNAPSHOT=submariner-0-22-20260326-225632-000  # Explicit snapshot
```

## Which Workflow Do I Need?

**Submariner bundle released (0.X.Y)?** → [update-catalog.md](.agents/workflows/update-catalog.md)

**Red Hat released new OCP version (including 5.0)?** → [add-ocp-version.md](.agents/workflows/add-ocp-version.md)

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
| `test` | Run unit + integration tests (~15s) |
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
| `clean` | Remove local binaries; preserve catalog edits |

## Repository Structure

- **Template:** Editable `catalog-template.yaml` auto-generates read-only `catalog-4-14/` through `catalog-4-22/` and `catalog-5-0/`
- **Scripts:** `scripts/update-bundle.sh` (workflow automation), `scripts/render-catalog.sh` (catalog builder)
- **Config:** `drop-versions.json` (OCP version mappings), `.tekton/` (Konflux pipelines for 4-16+)

**Build safety:** Tests run against disposable copies of candidate files, including uncommitted edits.
Catalog builds validate all staged output before replacing catalog directories.

**Catalog generation:** `make build-catalogs` filters the template per OCP version, renders via `opm alpha render-template`,
converts quay.io URLs to registry.redhat.io, and formats YAML.

## Troubleshooting

**VPN blocks `registry.redhat.io`** → Disconnect Red Hat VPN

**Not logged into cluster** → Run `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`

**"No push-event snapshot found"** → Wait for Konflux build (`oc get snapshot $SNAPSHOT -n submariner-tenant`) or use explicit:
`make update-bundle VERSION=0.22.1 SNAPSHOT=submariner-0-22-20260326-225632-000`

**Snapshot tests failed** → Wait for tests to pass or check status: `oc get snapshot $SNAPSHOT -n submariner-tenant -o jsonpath='{.metadata.annotations["test.appstudio.openshift.io/status"]}'`

## Glossary

- **Bundle**: Versioned operator package containing metadata, CRDs, and deployment manifests
- **Channel**: OLM upgrade path defining bundle sequence (e.g., `stable-0.22`)
- **FBC (File-Based Catalog)**: Declarative YAML format for distributing Kubernetes operators via OLM
- **Konflux**: Red Hat's CI/CD build platform for containerized applications
- **Mirror**: Image mirror configuration allowing unreleased quay.io workspace images to be accessed via registry.redhat.io during testing (ImageDigestMirrorSet)
- **OCP**: OpenShift Container Platform (full major/minor IDs such as 4-22 and 5-0)
- **OLM (Operator Lifecycle Manager)**: Kubernetes component managing operator installation and upgrades
- **OPM (Operator Package Manager)**: CLI tool for building and validating OLM catalogs (v1.56.0)
- **Snapshot**: Konflux build output artifact containing component images
- **Template**: Source file (`catalog-template.yaml`) that generates all OCP-specific catalogs
- **Version notation**:
  - Bundles: `0.X.Y` format (e.g., `submariner.v0.22.1`)
  - Snapshots: `submariner-0-X-YYYYMMDD-HHMMSS-NNN` format (e.g., `submariner-0-22-20260326-225632-000`)
  - Y-stream: `0-X` format representing minor version family (e.g., `0-22` for all v0.22.x releases)

### OCP onboarding and live E2E evidence

`make test-e2e` runs in a disposable copy with real Konflux and registry reads.
It checks the snapshot event label, exact bundle `csv-version`, completed
`TestPassed` results, every configured catalog, and the resulting fixture commit.
Use `TEST_VERSION=0.24.1 TEST_SNAPSHOT=<name> make test-e2e` to pin the input.
Pending, warning, or absent test results block this test; a detail message does
not override the reported status. It does not publish images or releases.

The cross-repository onboarding E2E runner lives in
`submariner-release-management/scripts/tests/e2e_fbc_onboarding.py`. It exercises
configuration generation, both pipeline events, mixed-major catalog rendering,
repeatability, and an OCP 5 base image serving the catalog through gRPC. An actual
OCP 5 operator installation and QE run remain separate required evidence.
