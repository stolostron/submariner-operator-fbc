#!/bin/bash
# test-cleanup-unreleased-ystreams.sh - Unit tests for cleanup_unreleased_ystreams function

set -euo pipefail
# shellcheck source=test/lib/isolate.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"
source "${REPO_ROOT_DIR}/test/lib/mock-commands.sh"

for fn in update_bundle_image ensure_mirror_ystream remove_bundle convert_released_bundles cleanup_unreleased_ystreams; do
  source_function_from_script "$fn" "${REPO_ROOT_DIR}/scripts/update-bundle.sh"
done

MIRRORS=.tekton/images-mirror-set.yaml

# Catalog with v0.22.1 and v0.23.1 on quay.io, one per Y-stream
setup_two_ystream_catalog() {
  git restore "$MIRRORS"
  setup_inline_catalog "schema: olm.template.basic
entries:
  - defaultChannel: stable-0.23
    name: submariner
    schema: olm.package
  - name: stable-0.21
    package: submariner
    schema: olm.channel
    entries:
      - name: ${TEST_BUNDLE_NAME_21_0}
  - name: stable-0.22
    package: submariner
    schema: olm.channel
    entries:
      - name: ${TEST_BUNDLE_NAME_22_1}
  - name: stable-0.23
    package: submariner
    schema: olm.channel
    entries:
      - name: ${TEST_BUNDLE_NAME_23_1}
  - name: ${TEST_BUNDLE_NAME_21_0}
    image: ${TEST_BUNDLE_REGISTRY_REAL_21_0}
    schema: olm.bundle
  - name: ${TEST_BUNDLE_NAME_22_1}
    image: ${TEST_BUNDLE_QUAY_22_ABC123}
    schema: olm.bundle
  - name: ${TEST_BUNDLE_NAME_23_1}
    image: ${TEST_BUNDLE_QUAY_23_DEF456}
    schema: olm.bundle"
}

assert_mirrors_only_target() {
  local streams
  streams=$(grep -oP -- '-[0-9]+-[0-9]+' "$MIRRORS" | sort -u | tr '\n' ' ')
  assert_equals "-$1 " "$streams" "Mirrors only point at $1"
}

#------------------------------------------------------------------------------
# Test Cases
#------------------------------------------------------------------------------

test_released_is_converted_and_kept() {
  setup_two_ystream_catalog
  create_skopeo_digest_mock "${TEST_SHA_ABC123}=released" "${TEST_SHA_DEF456}=released"

  local actual_code=0
  cleanup_unreleased_ystreams "0-25" >/dev/null 2>&1 || actual_code=$?

  assert_exit_code 0 "$actual_code" "Cleanup succeeds"
  assert_equals "${TEST_BUNDLE_REGISTRY_ABC123}" "$(get_bundle_image "${TEST_BUNDLE_NAME_22_1}")" "v0.22.1 converted"
  assert_equals "${TEST_BUNDLE_REGISTRY_DEF456}" "$(get_bundle_image "${TEST_BUNDLE_NAME_23_1}")" "v0.23.1 converted"
  assert_non_empty "$(get_channel_entry_for_bundle "stable-0.22" "${TEST_BUNDLE_NAME_22_1}")" "Channel entry kept"
  assert_mirrors_only_target "0-25"
}

test_absent_is_removed() {
  setup_two_ystream_catalog
  create_skopeo_digest_mock "${TEST_SHA_ABC123}=absent" "${TEST_SHA_DEF456}=absent"

  local actual_code=0
  cleanup_unreleased_ystreams "0-25" >/dev/null 2>&1 || actual_code=$?

  assert_exit_code 0 "$actual_code" "Cleanup succeeds"
  assert_empty "$(get_bundle_entry "${TEST_BUNDLE_NAME_22_1}")" "v0.22.1 removed"
  assert_empty "$(get_bundle_entry "${TEST_BUNDLE_NAME_23_1}")" "v0.23.1 removed"
  assert_non_empty "$(get_bundle_entry "${TEST_BUNDLE_NAME_21_0}")" "registry.redhat.io bundle untouched"
  assert_mirrors_only_target "0-25"
}

test_released_and_absent_together() {
  setup_two_ystream_catalog
  create_skopeo_digest_mock "${TEST_SHA_ABC123}=released" "${TEST_SHA_DEF456}=absent"

  cleanup_unreleased_ystreams "0-25" >/dev/null 2>&1

  assert_equals "${TEST_BUNDLE_REGISTRY_ABC123}" "$(get_bundle_image "${TEST_BUNDLE_NAME_22_1}")" "Released bundle converted"
  assert_empty "$(get_bundle_entry "${TEST_BUNDLE_NAME_23_1}")" "Absent bundle removed"
}

test_target_ystream_is_left_alone() {
  setup_two_ystream_catalog
  create_skopeo_digest_mock "${TEST_SHA_ABC123}=auth" "${TEST_SHA_DEF456}=released"

  local actual_code=0
  cleanup_unreleased_ystreams "0-22" >/dev/null 2>&1 || actual_code=$?

  # The target bundle isn't checked here, so its auth failure doesn't matter
  assert_exit_code 0 "$actual_code" "Cleanup succeeds"
  assert_equals "${TEST_BUNDLE_QUAY_22_ABC123}" "$(get_bundle_image "${TEST_BUNDLE_NAME_22_1}")" "Target bundle stays on quay.io"
  assert_equals "${TEST_BUNDLE_REGISTRY_DEF456}" "$(get_bundle_image "${TEST_BUNDLE_NAME_23_1}")" "Other Y-stream converted"
  assert_mirrors_only_target "0-22"
}

test_inconclusive_stops_without_changes() {
  local mode
  for mode in timeout auth network bare; do
    setup_two_ystream_catalog
    # The released bundle comes first: it must not be converted either
    create_skopeo_digest_mock "${TEST_SHA_ABC123}=released" "${TEST_SHA_DEF456}=$mode"

    local before_template before_mirrors output actual_code=0
    before_template=$(cat catalog-template.yaml)
    before_mirrors=$(cat "$MIRRORS")
    output=$(cleanup_unreleased_ystreams "0-25" 2>&1) || actual_code=$?

    assert_exit_code 1 "$actual_code" "$mode: cleanup fails"
    assert_equals "$before_template" "$(cat catalog-template.yaml)" "$mode: template unchanged"
    assert_equals "$before_mirrors" "$(cat "$MIRRORS")" "$mode: mirrors unchanged"
    assert_contains "${TEST_BUNDLE_NAME_23_1}" "$output" "$mode: error names the bundle"
    assert_contains "registry.redhat.io access" "$output" "$mode: error says what to check"
  done
}

test_bundle_without_digest_stops() {
  setup_two_ystream_catalog
  N="${TEST_BUNDLE_NAME_23_1}" yq eval '(.entries[] | select(.name == env(N) and .schema == "olm.bundle") | .image) = "quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-23:latest"' -i catalog-template.yaml
  create_skopeo_digest_mock "${TEST_SHA_ABC123}=released"

  local actual_code=0
  cleanup_unreleased_ystreams "0-25" >/dev/null 2>&1 || actual_code=$?

  assert_exit_code 1 "$actual_code" "Cleanup fails"
  assert_non_empty "$(get_bundle_entry "${TEST_BUNDLE_NAME_23_1}")" "Tag-based bundle not removed"
}

setup_mock_bin_dir

# test.sh shares one sandbox across tests, so don't leave the mirrors modified
trap 'git restore "$MIRRORS"; cleanup_mocks' EXIT

run_tests "test_"

exit $((TESTS_FAILED > 0 ? 1 : 0))
