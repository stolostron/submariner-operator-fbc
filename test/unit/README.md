# Unit Tests

Unit tests verify individual functions in isolation without external dependencies.

## Characteristics

- **Fast:** ~2 seconds total execution
- **Isolated:** No network, cluster, or registry access
- **Pure:** Test single functions with known inputs/outputs
- **Coverage:** 42 assertions across 24 test functions, including 6 table-driven test functions (covering 15 parameterized test cases)

## Test Files

| File                             | Assertions | What It Tests                                                     |
| -------------------------------- | ---------- | ----------------------------------------------------------------- |
| test-audit-bundle-urls.sh        | 19         | Bundle URL auditing and release status checking                   |
| test-catalog-queries.sh          | 7          | Bundle/channel existence checks, image retrieval, entry counting  |
| test-convert-released-bundles.sh | 14         | Bundle URL conversion (quay.io → registry.redhat.io)              |
| test-format-validators.sh        | 2          | SHA256 digest extraction, version format validation               |

## Running Unit Tests

Run all unit tests:

```bash
make test  # Runs unit + integration tests
```

Run a specific unit test:

```bash
./test/unit/test-catalog-queries.sh
```

## Test Structure

Each unit test follows this pattern:

```bash
#!/bin/bash
set -euo pipefail

# Source libraries
source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

# Define test functions
test_function_name() {
  # Arrange
  local input="test-value"
  
  # Act
  local result=$(function_under_test "$input")
  
  # Assert
  assert_equals "expected" "$result" "Description of what should happen"
}

# Run all test_* functions
run_tests
```

## Test Helpers

Unit tests use these assertion helpers from `scripts/lib/test-helpers.sh`:

- `assert_equals <expected> <actual> <message>` - Compare values
- `assert_exit_code <expected> <actual> <message>` - Check exit codes
- `assert_non_empty <value> <message>` - Verify non-empty
- `assert_empty <value> <message>` - Verify empty

## What Unit Tests Do NOT Test

- Network operations (use integration tests)
- File system changes (use integration tests)  
- External API calls (use E2E tests)
- Full workflow scenarios (use integration tests)

## Adding New Unit Tests

1. Create file: `test/unit/test-new-feature.sh`
2. Add header comment describing what it tests
3. Source catalog-functions.sh and test-helpers.sh
4. Write test_* functions
5. Tests run automatically in `make test`

## See Also

- [Integration Tests](../integration/README.md) - Workflow scenario testing
- [E2E Tests](../e2e/README.md) - Full end-to-end validation
- [Test Helpers](../../scripts/lib/test-helpers.sh) - Assertion framework
