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

# Assert exit code matches expected
# Supports two calling patterns:
#
#   2-param: assert_exit_code EXPECTED_CODE "description"
#     - Uses $? from the immediately previous command
#     - Example: some_function; assert_exit_code 0 "function succeeded"
#
#   3-param: assert_exit_code EXPECTED_CODE ACTUAL_CODE "description"
#     - Uses explicit exit code (useful when $? is already captured)
#     - Example: some_function; code=$?; assert_exit_code 0 "$code" "function succeeded"
#
# Note: For 2-param usage, assert_exit_code must be called immediately after
# the command to test, as $? is overwritten by each subsequent command.
assert_exit_code() {
  local expected_code="$1"
  local prev_exit_code=$?  # Capture immediately before any other commands
  local actual_code
  local description

  # Detect calling pattern by parameter count (more reliable than regex)
  if [ $# -eq 3 ]; then
    actual_code="$2"
    description="$3"
  else
    actual_code=$prev_exit_code
    description="${2:-}"
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
# Fixture Helpers
#------------------------------------------------------------------------------

# Setup test fixture by copying fixture file to catalog-template.yaml
# Parameters: $1 = fixture filename (default: fixture-0-21.yaml)
setup_fixture() {
  local fixture_file="${1:-fixture-0-21.yaml}"
  local repo_root="${REPO_ROOT_DIR:-$(realpath "$(dirname "${BASH_SOURCE[0]}")/../..")}"
  cp "${repo_root}/test/fixtures/${fixture_file}" catalog-template.yaml
}

# Cleanup test fixture
cleanup_fixture() {
  rm -f catalog-template.yaml
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

  # Get all functions matching pattern using compgen
  local test_functions
  # Convert shell glob pattern to list of matching function names
  test_functions=$(compgen -A function | grep "^${pattern//\*/.*}" || true)

  if [ -z "$test_functions" ]; then
    echo "No test functions found matching: $pattern"
    exit 1
  fi

  # Run each test function
  local failed_tests=()
  for test_func in $test_functions; do
    echo ""
    echo "Running: $test_func"
    if ! "$test_func"; then
      failed_tests+=("$test_func")
    fi
  done

  # Print summary
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
