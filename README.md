# Submariner Operator FBC

Automated catalog distribution for the Submariner multi-cluster networking operator.

## What is This?

This repository maintains file-based catalogs that make Submariner installable via OpenShift's Operator Lifecycle Manager.
It automates release updates, multi-version catalog generation, and production URL management across OCP 4-14 through 4-21.

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
| `clean` | Clean build/test artifacts and restore from git |

## Repository Structure

- **Template:** Editable `catalog-template.yaml` auto-generates read-only `catalog-4-14/` through `catalog-4-21/`
- **Scripts:** `scripts/update-bundle.sh` (workflow automation), `scripts/render-catalog.sh` (catalog builder)
- **Config:** `drop-versions.json` (OCP version mappings), `.tekton/` (Konflux pipelines for 4-16+)

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
- **OCP**: OpenShift Container Platform (versions 4-14 through 4-21; Konflux pipelines for 4-16+)
- **OLM (Operator Lifecycle Manager)**: Kubernetes component managing operator installation and upgrades
- **OPM (Operator Package Manager)**: CLI tool for building and validating OLM catalogs (v1.56.0)
- **Snapshot**: Konflux build output artifact containing component images
- **Template**: Source file (`catalog-template.yaml`) that generates all OCP-specific catalogs
- **Version notation**:
  - Bundles: `0.X.Y` format (e.g., `submariner.v0.22.1`)
  - Snapshots: `submariner-0-X-YYYYMMDD-HHMMSS-NNN` format (e.g., `submariner-0-22-20260326-225632-000`)
  - Y-stream: `0-X` format representing minor version family (e.g., `0-22` for all v0.22.x releases)
