#!/bin/bash
#
# test-validate-version.sh - Unit tests for validate_version_format function
#
# Tests version validation logic for Submariner versions (0.X.Y >= 0.18.0).
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Source functions under test
source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

#------------------------------------------------------------------------------
# Test Cases - Valid Versions
#------------------------------------------------------------------------------

test_validate_version_minimum() {
  validate_version_format "0.18.0" 2>/dev/null
  assert_exit_code 0 "Minimum supported version 0.18.0"
}

test_validate_version_valid_0_21_2() {
  validate_version_format "0.21.2" 2>/dev/null
  assert_exit_code 0 "Valid version 0.21.2"
}

#------------------------------------------------------------------------------
# Test Cases - Too Old (< 0.18.0)
#------------------------------------------------------------------------------

test_validate_version_too_old_0_17_6() {
  validate_version_format "0.17.6" 2>/dev/null || code=$?
  assert_exit_code 1 "$code" "Reject version 0.17.6 (< 0.18.0)"
}

#------------------------------------------------------------------------------
# Test Cases - Invalid Format
#------------------------------------------------------------------------------

test_validate_version_invalid_major_version() {
  validate_version_format "1.0.0" 2>/dev/null || code=$?
  assert_exit_code 1 "$code" "Reject major version != 0 (1.0.0)"
}

test_validate_version_invalid_missing_patch() {
  validate_version_format "0.21" 2>/dev/null || code=$?
  assert_exit_code 1 "$code" "Reject version without patch (0.21)"
}

test_validate_version_invalid_extra_components() {
  validate_version_format "0.21.2.1" 2>/dev/null || code=$?
  assert_exit_code 1 "$code" "Reject version with extra components (0.21.2.1)"
}

test_validate_version_empty_string() {
  validate_version_format "" 2>/dev/null || code=$?
  assert_exit_code 1 "$code" "Reject empty string"
}

test_validate_version_non_numeric_minor() {
  validate_version_format "0.abc.0" 2>/dev/null || code=$?
  assert_exit_code 1 "$code" "Reject non-numeric minor (0.abc.0)"
}

test_validate_version_non_numeric_patch() {
  validate_version_format "0.21.xyz" 2>/dev/null || code=$?
  assert_exit_code 1 "$code" "Reject non-numeric patch (0.21.xyz)"
}

#------------------------------------------------------------------------------
# Run Tests
#------------------------------------------------------------------------------

run_tests "test_validate_version_*"
