# Integration Tests

Integration tests verify complete workflow scenarios with strategic mocking of external dependencies.

## Characteristics

- **Fast:** ~4-5 seconds total execution
- **Realistic:** Tests full `update-bundle.sh` workflow
- **Strategic Mocking:** Mock external APIs (oc, skopeo, network) but use real catalogs
- **Coverage:** 14 assertions across 3 workflow scenarios

## Test Files

| File                     | Assertions | Scenario                                                       |
| ------------------------ | ---------- | -------------------------------------------------------------- |
| test-workflow-add.sh     | 7          | Adding first bundle of new Y-stream (e.g., v0.24.0)           |
| test-workflow-replace.sh | 4          | Skipping broken version (e.g., v0.23.2 replacing v0.23.1)     |
| test-workflow-update.sh  | 3          | Rebuilding existing bundle with new SHA                        |

## What Integration Tests Do

Integration tests validate the three main workflow scenarios:

### ADD Scenario

Tests adding the first release of a new minor version:

- Creates new channel (e.g., `stable-0.24`)
- Updates default channel pointer
- Adds bundle entry without `replaces` field
- Spot-checks one catalog (catalog-4-16) via `opm validate`
- Note: Tests skip full catalog rebuild for speed; production rebuilds all 8

### REPLACE Scenario

Tests skipping a problematic version:

- Replaces broken bundle in channel (e.g., v0.23.1 → v0.23.2)
- Updates `skipRange` to skip broken version
- Maintains upgrade path continuity
- Renames bundle files in catalogs

### UPDATE Scenario

Tests rebuilding an existing bundle with new SHA:

- Updates bundle SHA in catalog-template.yaml
- Preserves channel structure
- Spot-checks one catalog (catalog-4-16) with new SHA
- No structural changes (only SHA update)
- Note: Tests skip full catalog rebuild for speed; production updates all 8

## Running Integration Tests

Run all integration tests:

```bash
make test-scripts  # Runs unit + integration + legacy tests
```

Run a specific integration test:

```bash
./test/integration/test-workflow-add.sh
```

## Test Structure

Integration tests follow this pattern:

```bash
#!/bin/bash
set -euo pipefail

# Setup
BEFORE_TEST_COMMIT=$(git rev-parse HEAD)
cleanup() {
  git reset --hard "$BEFORE_TEST_COMMIT"
  ./scripts/reset-test-environment.sh
}
trap cleanup EXIT

# Copy fixture
cp test/fixtures/fixture-0-21.yaml catalog-template.yaml

# Mock external dependencies
oc() { ... }          # Mock Konflux API
skopeo() { ... }      # Mock registry checks
curl() { ... }        # Mock network calls

# Run actual workflow
./scripts/update-bundle.sh --version 0.24.0 --snapshot xyz

# Verify results
assert_file_contains "catalog-template.yaml" "submariner.v0.24.0"
assert_equals 17 "$(git status --short | wc -l)" "Expected 17 changed files"
```

## Mocking Strategy

Integration tests mock **external dependencies** but use **real components**:

### Mocked (External)

- ✅ `oc get snapshots` - Konflux cluster API
- ✅ `skopeo inspect` - Registry availability checks
- ✅ `curl` - GitHub/network requests

### Real (Internal)

- ✅ Catalog manipulation functions
- ✅ OPM template rendering
- ✅ OPM validation
- ✅ Git operations
- ✅ File system changes

This ensures tests are fast but still validate real catalog structure.

## Why Not Mock Everything?

Integration tests intentionally use real catalogs and real OPM because:

1. **Validates structure:** Real OPM catches schema errors
2. **Fast enough:** ~4 seconds is acceptable for CI
3. **High confidence:** Tests what actually ships
4. **Offline safe:** OPM validation works without network

## Fixtures

Integration tests use fixtures from `test/fixtures/`:

- `fixture-0-21.yaml` - Template with stable-0.21 channel (for ADD/UPDATE/REPLACE testing)

Fixtures contain real bundle SHAs so OPM validation passes.

## Adding New Integration Tests

1. Create file: `test/integration/test-workflow-<scenario>.sh`
2. Add descriptive header explaining the scenario
3. Set up cleanup trap to restore git state
4. Copy appropriate fixture
5. Mock external APIs (oc, skopeo, curl)
6. Run `update-bundle.sh` with test parameters
7. Assert expected file changes and content

## Debugging Integration Test Failures

```bash
# Run with verbose output
bash -x ./test/integration/test-workflow-add.sh

# Check what files changed
git status --short

# Inspect catalog-template.yaml
cat catalog-template.yaml | yq eval '.entries[]'

# Verify OPM validation
./bin/opm validate catalog-4-16/
```

## See Also

- [Unit Tests](../unit/README.md) - Function-level testing
- [E2E Tests](../e2e/README.md) - Full end-to-end validation
- [Fixtures](../fixtures/) - Test data
- [Test Helpers](../../scripts/lib/test-helpers.sh) - Assertion framework
