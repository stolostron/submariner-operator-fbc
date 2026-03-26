#!/bin/bash
# test-convert-released-bundles.sh - Unit tests for convert_released_bundles function

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"
source "${REPO_ROOT_DIR}/test/lib/mock-commands.sh"

source_function_from_script "update_bundle_image" "${REPO_ROOT_DIR}/scripts/update-bundle.sh"
source_function_from_script "convert_released_bundles" "${REPO_ROOT_DIR}/scripts/update-bundle.sh"

reset_bundle_arrays

get_bundle_url() {
  get_bundle_image "$1"
}

#------------------------------------------------------------------------------
# Test Cases
#------------------------------------------------------------------------------

test_no_convertible_bundles() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_21_0}
    image: ${TEST_BUNDLE_REGISTRY_ABC123}
    schema: olm.bundle"

  reset_bundle_arrays

  # Should return successfully without doing anything
  convert_released_bundles >/dev/null 2>&1
  local actual_code=$?

  assert_exit_code 0 "$actual_code" "Exits successfully when no bundles to convert"

  cleanup_inline_catalog
}

test_single_bundle_conversion() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_22_1}
    image: ${TEST_BUNDLE_QUAY_22_ABC123}
    schema: olm.bundle"

  CONVERTIBLE_BUNDLES=("${TEST_BUNDLE_NAME_22_1}")

  convert_released_bundles >/dev/null 2>&1
  local actual_code=$?

  assert_exit_code 0 "$actual_code" "Conversion succeeds"

  local new_url
  new_url=$(get_bundle_url "${TEST_BUNDLE_NAME_22_1}")

  assert_equals "${TEST_BUNDLE_REGISTRY_ABC123}" "$new_url" "URL converted to registry.redhat.io"

  # Verify SHA preserved
  local new_sha
  new_sha=$(extract_sha "$new_url")
  assert_equals "$TEST_SHA_ABC123" "$new_sha" "SHA preserved during conversion"

  cleanup_inline_catalog
}

test_multiple_bundle_conversion() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: submariner.v0.21.2
    image: ${TEST_BUNDLE_QUAY_21_ABC123}
    schema: olm.bundle
  - name: ${TEST_BUNDLE_NAME_22_1}
    image: ${TEST_BUNDLE_QUAY_22_DEF456}
    schema: olm.bundle"

  CONVERTIBLE_BUNDLES=("submariner.v0.21.2" "${TEST_BUNDLE_NAME_22_1}")

  convert_released_bundles >/dev/null 2>&1
  local actual_code=$?

  assert_exit_code 0 "$actual_code" "Multiple bundle conversion succeeds"

  # Check first bundle
  local url1
  url1=$(get_bundle_url "submariner.v0.21.2")
  assert_equals "${TEST_BUNDLE_REGISTRY_ABC123}" "$url1" "First bundle converted"

  # Check second bundle
  local url2
  url2=$(get_bundle_url "${TEST_BUNDLE_NAME_22_1}")
  assert_equals "${TEST_BUNDLE_REGISTRY_DEF456}" "$url2" "Second bundle converted"

  cleanup_inline_catalog
}

test_sha_preservation() {
  local test_sha="0a1743e8d528c04fb55daa6609dc6f14f17ac292a08bf17bfcb48f311f97e8a1"

  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_22_1}
    image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-22@sha256:${test_sha}
    schema: olm.bundle"

  CONVERTIBLE_BUNDLES=("${TEST_BUNDLE_NAME_22_1}")

  convert_released_bundles >/dev/null 2>&1

  local converted_sha
  converted_sha=$(extract_sha "$(get_bundle_url "${TEST_BUNDLE_NAME_22_1}")")

  local expected_sha
  expected_sha=$(extract_sha "registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${test_sha}")

  assert_equals "$expected_sha" "$converted_sha" "SHA exactly preserved (no truncation or modification)"

  cleanup_inline_catalog
}

test_already_converted_bundle() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_21_0}
    image: ${TEST_BUNDLE_REGISTRY_ABC123}
    schema: olm.bundle"

  # Shouldn't happen in practice (audit_bundle_urls filters these), but test graceful handling
  CONVERTIBLE_BUNDLES=("${TEST_BUNDLE_NAME_21_0}")

  # Should attempt conversion (will be no-op since extracting SHA and rebuilding same URL)
  convert_released_bundles >/dev/null 2>&1
  local actual_code=$?

  assert_exit_code 0 "$actual_code" "Handles already-converted bundles gracefully"

  local url
  url=$(get_bundle_url "${TEST_BUNDLE_NAME_21_0}")
  assert_equals "${TEST_BUNDLE_REGISTRY_ABC123}" "$url" "URL unchanged"

  cleanup_inline_catalog
}

test_mixed_conversion() {
  local sha1="eeeea5ed12345678eeeea5ed12345678eeeea5ed12345678eeeea5ed12345678"
  local sha2="fff0eea12345678fff0eea12345678fff0eea12345678fff0eea123456789012"

  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_22_1}
    image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-22@sha256:${sha1}
    schema: olm.bundle
  - name: ${TEST_BUNDLE_NAME_23_1}
    image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-23@sha256:${sha2}
    schema: olm.bundle"

  # Only convert v0.22.1, leave v0.23.1 as quay.io
  CONVERTIBLE_BUNDLES=("${TEST_BUNDLE_NAME_22_1}")

  convert_released_bundles >/dev/null 2>&1

  local url1
  url1=$(get_bundle_url "${TEST_BUNDLE_NAME_22_1}")
  local expected_url1="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${sha1}"
  assert_equals "$expected_url1" "$url1" "Released bundle converted"

  local url2
  url2=$(get_bundle_url "${TEST_BUNDLE_NAME_23_1}")
  local expected_url2="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-23@sha256:${sha2}"
  assert_equals "$expected_url2" "$url2" "Unreleased bundle unchanged"

  cleanup_inline_catalog
}

test_bundle_not_in_catalog() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_21_0}
    image: registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${TEST_SHA_ABC123}
    schema: olm.bundle"

  # Try to convert a bundle that doesn't exist
  CONVERTIBLE_BUNDLES=("submariner.v0.99.9")

  # Should handle gracefully (get_bundle_image returns empty, extract_sha returns empty)
  actual_code=0
  convert_released_bundles >/dev/null 2>&1 || actual_code=$?

  # Conversion will fail because it can't find the bundle
  assert_exit_code 1 "$actual_code" "Fails when bundle not found in catalog"

  cleanup_inline_catalog
}

test_conversion_output_format() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_22_1}
    image: ${TEST_BUNDLE_QUAY_22_ABC123}
    schema: olm.bundle"

  # shellcheck disable=SC2034  # Variable set here, read by convert_released_bundles() in global scope
  CONVERTIBLE_BUNDLES=("${TEST_BUNDLE_NAME_22_1}")

  local output
  output=$(convert_released_bundles 2>&1)

  assert_contains "Converting" "$output" "Output contains conversion progress messages"

  cleanup_inline_catalog
}

run_tests "test_"

cleanup_mocks

exit $((TESTS_FAILED > 0 ? 1 : 0))
