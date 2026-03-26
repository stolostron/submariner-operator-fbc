# CLAUDE.md

This file provides workflow guidance for Claude Code when working with this repository.
The `@` references below are markdown includes that import full workflow documents.

## Which Workflow Do I Need?

**Choose based on your task:**

- **Submariner bundle released?** → [Update FBC Catalog](.agents/workflows/update-catalog.md)
- **Need to sync prod URLs?** → [Update Catalog Template to Production URL](.agents/workflows/update-prod-url.md)
- **New OpenShift version?** → [Add Support for New OCP Version](.agents/workflows/add-ocp-version.md)

## Quick Reference

**Version notation:** See [README Glossary](README.md#glossary)

**Common commands:**

```bash
make update-bundle VERSION=0.22.1              # Most common: update with new SHA
make build-catalogs validate-catalogs          # Build and validate all catalogs
make test                                        # Run fast tests (~15s)
```

## Constraints

**Mirror file size limit:** `.tekton/images-mirror-set.yaml` limited to 4096 bytes (Tekton task result limit).
Only one unreleased Y-stream allowed in mirrors at a time. When adding or updating any unreleased bundle,
the `update-bundle` script automatically removes unreleased bundles from all other Y-streams.

**Released bundles exempt:** Bundles using registry.redhat.io URLs don't need mirrors and don't count toward the limit.

---

## Update FBC Catalog with New Bundle

@.agents/workflows/update-catalog.md

## Update Catalog Template to Production Bundle URL

@.agents/workflows/update-prod-url.md

## Add Support for New OCP Version

@.agents/workflows/add-ocp-version.md
