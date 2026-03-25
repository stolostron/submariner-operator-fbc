#!/bin/bash
#
# test-helpers.sh - Test assertion helpers for bash unit tests
#
# Provides assertion functions for bash test scripts following the
# existing test patterns in this repository.
#

# Global test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

#------------------------------------------------------------------------------
# Basic Assertions
#------------------------------------------------------------------------------

# Assert two strings are equal
# Parameters: $1 = expected, $2 = actual, $3 = optional description
assert_equals() {
  local expected="$1"
  local actual="$2"
  local description="${3:-}"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ "$expected" = "$actual" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ ${description:-Assertion passed}"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ ${description:-Assertion failed}"
    echo "    Expected: '$expected'"
    echo "    Actual:   '$actual'"
    return 1
  fi
}

# Assert value is non-empty
# Parameters: $1 = value, $2 = optional description
assert_non_empty() {
  local value="$1"
  local description="${2:-Value is non-empty}"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -n "$value" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ $description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ $description (value is empty)"
    return 1
  fi
}

# Assert value is empty
# Parameters: $1 = value, $2 = optional description
assert_empty() {
  local value="$1"
  local description="${2:-Value is empty}"

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ -z "$value" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ $description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ $description (value: '$value')"
    return 1
  fi
}

# Assert exit code matches expected
# Parameters:
#   $1 = expected exit code
#   $2 = actual exit code (must be explicitly captured)
#   $3 = optional description
#
# Example:
#   some_function; code=$?
#   assert_exit_code 0 "$code" "function succeeded"
#
# Note: Always capture exit code explicitly before calling this function.
assert_exit_code() {
  local expected_code="$1"
  local actual_code="$2"
  local description="${3:-}"

  # Validate that exit codes are integers
  if ! [[ "$expected_code" =~ ^[0-9]+$ ]]; then
    echo "  ✗ ERROR: expected_code must be integer, got: '$expected_code'" >&2
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  if ! [[ "$actual_code" =~ ^[0-9]+$ ]]; then
    echo "  ✗ ERROR: actual_code must be integer, got: '$actual_code'" >&2
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi

  TESTS_RUN=$((TESTS_RUN + 1))

  if [ "$expected_code" -eq "$actual_code" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ ${description:-Exit code $expected_code}"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ ${description:-Exit code mismatch}"
    echo "    Expected: $expected_code"
    echo "    Actual:   $actual_code"
    return 1
  fi
}

#------------------------------------------------------------------------------
# YAML Query Helpers
#------------------------------------------------------------------------------

# Extract field from yq output (avoids echo | yq pattern)
# Parameters: $1 = yq output (captured YAML), $2 = field path
# Example: REPLACES=$(get_yq_field "$CHANNEL_ENTRY" '.replaces')
get_yq_field() {
  if [ $# -lt 2 ]; then
    echo "ERROR: get_yq_field requires 2 parameters: yaml_content field_path" >&2
    return 1
  fi
  echo "$1" | yq eval "$2" -
}

# Get bundle entry from catalog-template.yaml
# Parameters: $1 = bundle name (e.g., "submariner.v0.21.2")
# Returns: full bundle entry YAML or empty if not found
get_bundle_entry_from_catalog() {
  local bundle_name="$1"
  # Validate bundle name format to prevent injection
  if [[ ! "$bundle_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "ERROR: Invalid bundle name format: $bundle_name" >&2
    return 1
  fi
  yq eval ".entries[] | select(.schema == \"olm.bundle\" and .name == \"${bundle_name}\")" catalog-template.yaml
}

# Get channel entry for a specific bundle
# Parameters: $1 = channel name, $2 = bundle name
# Returns: channel entry YAML or empty if not found
get_channel_entry_for_bundle() {
  local channel_name="$1"
  local bundle_name="$2"
  # Validate channel and bundle name formats to prevent injection
  if [[ ! "$channel_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "ERROR: Invalid channel name format: $channel_name" >&2
    return 1
  fi
  if [[ ! "$bundle_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "ERROR: Invalid bundle name format: $bundle_name" >&2
    return 1
  fi
  yq eval ".entries[] | select(.schema == \"olm.channel\" and .name == \"${channel_name}\") | .entries[] | select(.name == \"${bundle_name}\")" catalog-template.yaml
}

# Assert array has expected number of elements
# Parameters: $1 = array name (string), $2 = expected count, $3 = description
assert_array_length() {
  local array_name="$1"
  local expected_count="$2"
  local description="${3:-Array length matches}"

  # Use nameref (bash 4.3+) for safe indirect expansion without eval injection risks
  local -n array_ref="$array_name"
  local actual_count="${#array_ref[@]}"

  assert_equals "$expected_count" "$actual_count" "$description"
}

# Assert string contains substring
# Parameters: $1 = substring to find, $2 = text to search, $3 = description
assert_contains() {
  local substring="$1"
  local text="$2"
  local description="${3:-Text contains substring}"

  TESTS_RUN=$((TESTS_RUN + 1))

  # Use -F for fixed-string matching (prevents regex injection if substring is user-controlled)
  if echo "$text" | grep -qF "$substring"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ $description"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ $description"
    echo "    Expected substring: '$substring'"
    return 1
  fi
}

#------------------------------------------------------------------------------
# Test Setup Helpers
#------------------------------------------------------------------------------

# Reset bundle categorization arrays
# Call before running audit_bundle_urls() or convert_released_bundles()
reset_bundle_arrays() {
  # shellcheck disable=SC2034  # Global array populated by audit_bundle_urls(), read by convert_released_bundles()
  CONVERTIBLE_BUNDLES=()
  # shellcheck disable=SC2034  # Global array populated by audit_bundle_urls(), used in audit summary output
  UNRELEASED_BUNDLES=()
}

# Extract and source function from script file
# Parameters: $1 = function name, $2 = script path
# Example: source_function_from_script "audit_bundle_urls" "${REPO_ROOT_DIR}/scripts/update-bundle.sh"
source_function_from_script() {
  if [ $# -lt 2 ]; then
    echo "ERROR: source_function_from_script requires 2 parameters: function_name script_path" >&2
    return 1
  fi
  local function_name="$1"
  local script_path="$2"

  if [ ! -f "$script_path" ]; then
    echo "ERROR: Script file not found: $script_path" >&2
    return 1
  fi

  local temp_file="/tmp/extract-func-$$.sh"

  awk "/^${function_name}\\(\\) \\{/,/^}$/ {print}" "$script_path" > "$temp_file"

  if [ ! -s "$temp_file" ]; then
    echo "ERROR: Function '$function_name' not found in $script_path" >&2
    rm -f "$temp_file"
    return 1
  fi

  # shellcheck disable=SC1090  # Dynamic source of extracted function
  source "$temp_file"
  rm -f "$temp_file"
}

#------------------------------------------------------------------------------
# Fixture Helpers
#------------------------------------------------------------------------------

# Setup test fixture by copying fixture file to catalog-template.yaml
# Parameters: $1 = fixture filename (default: fixture-0-21.yaml)
#             Can use syntax "fixture-name:modifier" for dynamic modifications
setup_fixture() {
  local fixture_spec="${1:-fixture-0-21.yaml}"
  local repo_root="${REPO_ROOT_DIR:-$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")}"

  # Parse fixture spec: "name.yaml" or "name.yaml:modifier"
  local fixture_file="${fixture_spec%%:*}"
  local modifier="${fixture_spec#*:}"
  [[ "$modifier" == "$fixture_spec" ]] && modifier=""

  local fixture_path="${repo_root}/test/fixtures/${fixture_file}"
  if [ ! -f "$fixture_path" ]; then
    echo "ERROR: Fixture file not found: $fixture_path" >&2
    return 1
  fi

  cp "$fixture_path" catalog-template.yaml

  if [ -n "$modifier" ]; then
    case "$modifier" in
      add-empty-0-22)
        yq eval '.entries += [{"name": "stable-0.22", "package": "submariner", "schema": "olm.channel", "entries": []}]' -i catalog-template.yaml
        ;;
      *)
        echo "ERROR: Unknown fixture modifier: $modifier" >&2
        return 1
        ;;
    esac
  fi
}

# Cleanup test fixture
cleanup_fixture() {
  # Restore catalog-template.yaml from git instead of just deleting it
  # This ensures git stays clean for subsequent tests
  git restore catalog-template.yaml 2>/dev/null || rm -f catalog-template.yaml
}

# Setup inline catalog for tests that need custom YAML content
# Parameters: $1 = catalog content as string
setup_inline_catalog() {
  local catalog_content="$1"
  echo "$catalog_content" > catalog-template.yaml
}

# Cleanup inline catalog
cleanup_inline_catalog() {
  rm -f catalog-template.yaml
}

#------------------------------------------------------------------------------
# Integration Test Helpers
#------------------------------------------------------------------------------

# Validate prerequisites for integration tests
# Parameters: $1 = optional fixture path (default: test/fixtures/fixture-0-21.yaml)
validate_integration_test_prerequisites() {
  local fixture="${1:-test/fixtures/fixture-0-21.yaml}"

  if [ ! -f "$fixture" ]; then
    echo "ERROR: Test fixture not found: $fixture"
    return 1
  fi

  if ! git diff --quiet 2>/dev/null; then
    echo "ERROR: Git working tree has uncommitted changes. Commit or stash them first."
    return 1
  fi
}

# Initialize integration test environment (combines common setup)
# Parameters: $1 = optional fixture path (default: test/fixtures/fixture-0-21.yaml)
initialize_integration_test() {
  local fixture="${1:-test/fixtures/fixture-0-21.yaml}"

  INITIAL_COMMIT=$(git rev-parse HEAD)
  export INITIAL_COMMIT

  # Define cleanup function that handles both mocks and git restore
  cleanup() {
    cleanup_mocks 2>/dev/null || true
    unset SKIP_BUILD_CATALOGS 2>/dev/null || true
    git reset --hard "$INITIAL_COMMIT" > /dev/null 2>&1 || true
    ./scripts/reset-test-environment.sh "$INITIAL_COMMIT" > /dev/null 2>&1 || true
  }

  export -f cleanup
  trap cleanup EXIT

  cp "$fixture" catalog-template.yaml
}

# Validate catalog directory with opm
# Parameters: $1 = optional catalog directory (default: catalog-4-16)
validate_catalog() {
  local catalog_dir="${1:-catalog-4-16}"
  local opm="${OPM:-bin/opm}"

  echo "Validating real $catalog_dir..."
  if [ -d "$catalog_dir" ]; then
    $opm validate "$catalog_dir/"
  else
    echo "Warning: $catalog_dir not found, skipping validation"
  fi
}

# Print test summary with pass/fail status
# Parameters: $1 = test name
print_test_summary() {
  local test_name="${1:-test}"

  echo ""
  echo "=================================="
  echo "Test Summary:"
  echo "  Total:  $TESTS_RUN"
  echo "  Passed: $TESTS_PASSED"
  echo "  Failed: $TESTS_FAILED"
  echo ""

  if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "[SUCCESS] $test_name test passed"
    return 0
  else
    echo "FAILED: $test_name test"
    return 1
  fi
}

#------------------------------------------------------------------------------
# Test Execution
#------------------------------------------------------------------------------

# Run all test functions matching a pattern
# Parameters: $1 = test function name pattern (e.g., "test_*")
run_tests() {
  local pattern="$1"

  echo ""
  echo "Running tests matching: $pattern"
  echo "=================================="

  local test_functions
  test_functions=$(compgen -A function | grep "^${pattern//\*/.*}" || true)

  if [ -z "$test_functions" ]; then
    echo "No test functions found matching: $pattern"
    exit 1
  fi

  local failed_tests=()
  for test_func in $test_functions; do
    echo ""
    echo "Running: $test_func"

    # Run test and ensure cleanup runs even if test fails
    if ! "$test_func"; then
      failed_tests+=("$test_func")
    fi

    # Cleanup after each test to ensure git stays clean
    # This catches cases where test fails before calling cleanup_fixture()
    cleanup_fixture 2>/dev/null || true
  done

  echo ""
  echo "=================================="
  echo "Test Summary:"
  echo "  Total:  $TESTS_RUN"
  echo "  Passed: $TESTS_PASSED"
  echo "  Failed: $TESTS_FAILED"

  if [ ${#failed_tests[@]} -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for test_func in "${failed_tests[@]}"; do
      echo "  - $test_func"
    done
    echo ""
    exit 1
  fi

  echo ""
  echo "[SUCCESS] All tests passed"
}
