#!/bin/bash
# test-format-validators.sh - Unit tests for format validation functions

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"

# Test data: version|expected_exit_code|description
version_test_cases=(
  # Valid versions
  "${TEST_MIN_VERSION}|0|Minimum supported version"
  "0.21.2|0|Valid version 0.21.2"

  # Too old (< 0.18.0)
  "${TEST_VERSION_TOO_OLD}|1|Reject pre-minimum version"

  # Invalid format
  "1.0.0|1|Reject major version != 0 (1.0.0)"
  "0.21|1|Reject version without patch (0.21)"
  "0.21.2.1|1|Reject version with extra components (0.21.2.1)"
  "|1|Reject empty string"
  "0.abc.0|1|Reject non-numeric minor (0.abc.0)"
  "0.21.xyz|1|Reject non-numeric patch (0.21.xyz)"
)

test_validate_version_table_driven() {
  local failed=0

  for test_case in "${version_test_cases[@]}"; do
    IFS='|' read -r version expected_code description <<< "$test_case"

    local actual_code=0
    validate_version_format "$version" 2>/dev/null || actual_code=$?

    assert_exit_code "$expected_code" "$actual_code" "$description" || failed=$((failed + 1))
  done

  return $failed
}

# Test data: url|expected_sha|description
sha_test_cases=(
  # Valid extraction
  "quay.io/repo/image@sha256:7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99|7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99|Extract SHA from URL"

  # Invalid/unsupported formats
  "quay.io/repo/image:latest||Tag-based URL returns empty"
  "quay.io/repo/image@sha256:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz||Reject SHA with non-hex characters"
  "quay.io/repo/image@sha384:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef||Return empty for SHA384 (only SHA256 supported)"
  "quay.io/repo/image@sha256:abc123||Reject SHA shorter than 64 chars"
  "quay.io/repo/image@sha256:||Empty digest returns empty"
  "quay.io/repo/image@sha256:7A23EB13E0197B4EAB7A645FF18C1ABD63A39234C55C0E19B8C1C39AA2FE6E99||Uppercase hex not supported (regex requires lowercase)"

  # Edge case: too long (extracts first 64 chars)
  "quay.io/repo/image@sha256:7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e997a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99|7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99|Extract first 64 chars from longer string"
)

test_extract_sha_table_driven() {
  local failed=0

  for test_case in "${sha_test_cases[@]}"; do
    IFS='|' read -r url expected description <<< "$test_case"

    local result
    result=$(extract_sha "$url")
    assert_equals "$expected" "$result" "$description" || failed=$((failed + 1))
  done

  return $failed
}

run_tests "test_*"
