# End-to-End (E2E) Tests

These tests use real external dependencies (Konflux cluster, container registries, network).
They take ~45 seconds and require:

- **Cluster access:** `oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/`
- **Registry auth:** `podman login registry.redhat.io` (uses Red Hat credentials)
- **Network:** Must be off RH VPN (VPN blocks registry.redhat.io)

Run with: `make test-e2e`

**Not run by default:** `make test` runs only fast tests (unit + integration)

## What E2E Tests Validate

End-to-end tests verify the complete workflow with real external services:

- **Real Konflux cluster** - Fetches actual snapshots via `oc get snapshots`
- **Real registries** - Checks bundle availability via `skopeo inspect`
- **Real catalog builds** - Runs full `make build-catalogs` (~30s)
- **Real OPM validation** - Validates generated catalogs with `opm validate`

## When to Run E2E Tests

Use E2E tests for:

- Pre-release validation before merging critical changes
- Debugging Konflux integration issues
- Verifying changes work across all OCP versions
- Testing with actual snapshots and registry data

**Do NOT run for:**

- Quick iteration during development (use `make test` instead)
- CI/CD pipelines (too slow, external dependencies)
- Testing pure logic (use unit tests instead)

## Example Usage

```bash
# Login to Konflux cluster first
oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/

# Run E2E tests
make test-e2e
```

## Troubleshooting

**Authentication errors**: Run `oc login` again

**Registry timeouts**: Disconnect from RH VPN

**Snapshot not found**: Verify a recent Konflux build exists for the version being tested

**Slow execution**: Test runs in ~45s. Use fast unit/integration tests (~15s) for quicker feedback.
