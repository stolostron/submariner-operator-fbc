#!/bin/bash
#
# test-extract-sha.sh - Unit tests for extract_sha function
#
# Tests SHA256 extraction from container image URLs with various formats.
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Source functions under test
source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

#------------------------------------------------------------------------------
# Test Cases
#------------------------------------------------------------------------------

test_extract_sha_valid() {
  local sha="7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99"
  local result=$(extract_sha "quay.io/repo/image@sha256:$sha")
  assert_equals "$sha" "$result" "Extract SHA from URL"
}

test_extract_sha_no_sha() {
  assert_equals "" "$(extract_sha "quay.io/repo/image:latest")" "Tag-based URL returns empty"
}

test_extract_sha_invalid_sha_non_hex() {
  local result=$(extract_sha "quay.io/repo/image@sha256:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
  assert_equals "" "$result" "Reject SHA with non-hex characters"
}

test_extract_sha_sha384_not_supported() {
  local url="quay.io/repo/image@sha384:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  local result=$(extract_sha "$url")
  assert_equals "" "$result" "Return empty for SHA384 (only SHA256 supported)"
}

test_extract_sha_too_short() {
  local result=$(extract_sha "quay.io/repo/image@sha256:abc123")
  assert_equals "" "$result" "Reject SHA shorter than 64 chars"
}

test_extract_sha_too_long() {
  local sha="7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e997a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99"  # 128 chars
  local result=$(extract_sha "quay.io/repo/image@sha256:$sha")
  local expected="7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99"  # First 64 chars
  assert_equals "$expected" "$result" "Extract first 64 chars from longer string"
}

test_extract_sha_empty_digest() {
  assert_equals "" "$(extract_sha "quay.io/repo/image@sha256:")" "Empty digest returns empty"
}

test_extract_sha_uppercase_hex() {
  local sha_upper="7A23EB13E0197B4EAB7A645FF18C1ABD63A39234C55C0E19B8C1C39AA2FE6E99"
  local result=$(extract_sha "quay.io/repo/image@sha256:$sha_upper")
  assert_equals "" "$result" "Uppercase hex not supported (regex requires lowercase)"
}

#------------------------------------------------------------------------------
# Run Tests
#------------------------------------------------------------------------------

run_tests "test_extract_sha_*"
