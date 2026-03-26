#!/bin/bash
# test-audit-bundle-urls.sh - Unit tests for audit_bundle_urls function

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"
source "${REPO_ROOT_DIR}/test/lib/mock-commands.sh"

source_function_from_script "audit_bundle_urls" "${REPO_ROOT_DIR}/scripts/update-bundle.sh"

reset_bundle_arrays

#------------------------------------------------------------------------------
# Test Cases
#------------------------------------------------------------------------------

test_no_quay_bundles() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: submariner.v0.21.0
    image: ${TEST_BUNDLE_REGISTRY_ABC123}
    schema: olm.bundle"

  reset_bundle_arrays

  audit_bundle_urls >/dev/null 2>&1

  assert_array_length "CONVERTIBLE_BUNDLES" "0" "No convertible bundles when all use registry.redhat.io"
  assert_array_length "UNRELEASED_BUNDLES" "0" "No unreleased bundles when all use registry.redhat.io"

  cleanup_inline_catalog
}

test_single_released_bundle() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: submariner.v0.22.1
    image: ${TEST_BUNDLE_QUAY_22_ABC123}
    schema: olm.bundle"

  create_skopeo_mock 0

  reset_bundle_arrays

  audit_bundle_urls >/dev/null 2>&1

  assert_array_length "CONVERTIBLE_BUNDLES" "1" "One convertible bundle found"
  assert_array_length "UNRELEASED_BUNDLES" "0" "No unreleased bundles"
  assert_equals "submariner.v0.22.1" "${CONVERTIBLE_BUNDLES[0]}" "Correct bundle name in CONVERTIBLE array"

  cleanup_inline_catalog
}

test_single_unreleased_bundle() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: submariner.v0.23.1
    image: ${TEST_BUNDLE_QUAY_23_DEF456}
    schema: olm.bundle"

  create_skopeo_mock 1

  reset_bundle_arrays

  audit_bundle_urls >/dev/null 2>&1

  assert_array_length "CONVERTIBLE_BUNDLES" "0" "No convertible bundles"
  assert_array_length "UNRELEASED_BUNDLES" "1" "One unreleased bundle found"
  assert_equals "submariner.v0.23.1" "${UNRELEASED_BUNDLES[0]}" "Correct bundle name in UNRELEASED array"

  cleanup_inline_catalog
}

test_timeout_handling() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_22_0}
    image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-22@sha256:timeout0123456789abcdeftimeout0123456789abcdeftimeout0123456789a
    schema: olm.bundle"

  create_skopeo_mock 124

  reset_bundle_arrays

  audit_bundle_urls >/dev/null 2>&1

  assert_array_length "CONVERTIBLE_BUNDLES" "0" "Timeout bundles not added to CONVERTIBLE"
  assert_array_length "UNRELEASED_BUNDLES" "0" "Timeout bundles not added to UNRELEASED (indeterminate state)"

  cleanup_inline_catalog
}

test_mixed_bundle_status() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: submariner.v0.21.0
    image: ${TEST_BUNDLE_REGISTRY_REAL}
    schema: olm.bundle
  - name: submariner.v0.22.1
    image: ${TEST_BUNDLE_QUAY_22_ABC123}
    schema: olm.bundle
  - name: submariner.v0.23.1
    image: ${TEST_BUNDLE_QUAY_23_DEF456}
    schema: olm.bundle"

  # Create a smart mock that returns different exit codes based on SHA
  cat > "${MOCK_BIN_DIR}/skopeo" <<EOF
#!/bin/bash
# Exit 0 for abc123 SHA (v0.22.1), 1 for def456 SHA (v0.23.1)
if echo "\$@" | grep -qF "${TEST_SHA_ABC123}"; then
  exit 0
else
  exit 1
fi
EOF
  chmod +x "${MOCK_BIN_DIR}/skopeo"

  reset_bundle_arrays

  audit_bundle_urls >/dev/null 2>&1

  assert_array_length "CONVERTIBLE_BUNDLES" "1" "One convertible bundle (v0.22.1)"
  assert_array_length "UNRELEASED_BUNDLES" "1" "One unreleased bundle (v0.23.1)"
  assert_equals "submariner.v0.22.1" "${CONVERTIBLE_BUNDLES[0]}" "v0.22.1 is convertible"
  assert_equals "submariner.v0.23.1" "${UNRELEASED_BUNDLES[0]}" "v0.23.1 is unreleased"

  cleanup_inline_catalog
}

test_multiple_released_bundles() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: submariner.v0.21.2
    image: ${TEST_BUNDLE_QUAY_21_ABC123}
    schema: olm.bundle
  - name: submariner.v0.22.1
    image: ${TEST_BUNDLE_QUAY_22_DEF456}
    schema: olm.bundle"

  create_skopeo_mock 0

  reset_bundle_arrays

  audit_bundle_urls >/dev/null 2>&1

  assert_array_length "CONVERTIBLE_BUNDLES" "2" "Two convertible bundles found"
  assert_array_length "UNRELEASED_BUNDLES" "0" "No unreleased bundles"

  cleanup_inline_catalog
}

test_bundle_without_sha() {
  setup_inline_catalog "schema: olm.template.basic
entries:
  - name: ${TEST_BUNDLE_NAME_22_0}
    image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-22:latest
    schema: olm.bundle"

  reset_bundle_arrays

  # Should handle gracefully with warning
  audit_bundle_urls >/dev/null 2>&1

  assert_array_length "CONVERTIBLE_BUNDLES" "0" "Tag-based URLs skipped (no SHA to check)"
  assert_array_length "UNRELEASED_BUNDLES" "0" "Tag-based URLs not categorized"

  cleanup_inline_catalog
}

test_missing_catalog_file() {
  rm -f catalog-template.yaml

  reset_bundle_arrays

  # Should exit with error - run in subshell to capture exit code without exiting test
  local actual_code=0
  (audit_bundle_urls >/dev/null 2>&1) || actual_code=$?

  assert_exit_code 1 "$actual_code" "Exits with error when catalog-template.yaml missing"
}

setup_mock_bin_dir

run_tests "test_"

cleanup_mocks

exit $((TESTS_FAILED > 0 ? 1 : 0))
