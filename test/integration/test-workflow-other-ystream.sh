#!/bin/bash
# test-workflow-other-ystream.sh - Integration test for bundles from other Y-streams
#
# Scenario: A bundle from another Y-stream is still on quay.io when update-bundle runs
# Why: A released bundle must be converted, not deleted, and an unknown one must stop the run

set -euo pipefail
# shellcheck source=test/lib/isolate.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/mock-commands.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== Integration Test: Other Y-stream Workflow ==="
echo ""

validate_integration_test_prerequisites || exit 1
initialize_integration_test

MIRRORS=.tekton/images-mirror-set.yaml
OTHER_NAME="$TEST_BUNDLE_NAME_23_1"
OTHER_SHA="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
OTHER_QUAY="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-23@sha256:$OTHER_SHA"
OTHER_PROD="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:$OTHER_SHA"
NEW_VERSION=0.25.0
NEW_NAME="submariner.v$NEW_VERSION"
NEW_QUAY="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-25@sha256:$TEST_SHA_FEDCBA"

export SKIP_BUILD_CATALOGS=true

# Start each test from the fixture plus a quay.io bundle from another Y-stream
setup_catalog() {
  git reset -q --hard "$INITIAL_COMMIT"
  cp test/fixtures/fixture-0-21.yaml catalog-template.yaml
  NAME="$OTHER_NAME" IMAGE="$OTHER_QUAY" yq eval '
    .entries += [{"name": "stable-0.23", "package": "submariner", "schema": "olm.channel", "entries": [{"name": env(NAME), "skipRange": ">=0.18.0 <0.23.1"}]}] |
    .entries += [{"name": env(NAME), "image": env(IMAGE), "schema": "olm.bundle"}]' -i catalog-template.yaml
  git add catalog-template.yaml
  git commit -qm "test catalog"
}

# Run update-bundle.sh, setting RUN_CODE and RUN_OUTPUT
# Parameters: update-bundle.sh arguments
run_update() {
  RUN_CODE=0
  RUN_OUTPUT=$(./scripts/update-bundle.sh "$@" 2>&1) || RUN_CODE=$?
}

assert_mirrors_only_target() {
  local streams
  streams=$(grep -oP -- '-[0-9]+-[0-9]+' "$MIRRORS" | sort -u | tr '\n' ' ')
  assert_equals "-$1 " "$streams" "Mirrors only point at $1"
}

# Assert the run failed and left the checkout exactly as setup_catalog made it
# Parameters: $1 = description
assert_stopped_without_changes() {
  assert_exit_code 1 "$RUN_CODE" "$1: run stops"
  assert_contains "$OTHER_NAME" "$RUN_OUTPUT" "$1: error names the bundle"
  assert_equals "test catalog" "$(git log -1 --format=%s)" "$1: no commit created"
  assert_empty "$(git status --porcelain -- catalog-template.yaml "$MIRRORS")" "$1: template and mirrors unchanged"
}

#------------------------------------------------------------------------------
# Test Cases
#------------------------------------------------------------------------------

test_add_converts_released_bundle() {
  setup_catalog
  create_oc_mock submariner-0-25-abc123 "$NEW_QUAY" "$NEW_VERSION"
  create_skopeo_digest_mock "$OTHER_SHA=released"

  run_update --version "$NEW_VERSION" --snapshot submariner-0-25-abc123

  assert_exit_code 0 "$RUN_CODE" "ADD succeeds"
  assert_equals "$OTHER_PROD" "$(get_bundle_image "$OTHER_NAME")" "Released bundle converted"
  assert_non_empty "$(get_channel_entry_for_bundle stable-0.23 "$OTHER_NAME")" "Released bundle stays in its channel"
  assert_equals "$NEW_QUAY" "$(get_bundle_image "$NEW_NAME")" "New bundle added"
  assert_mirrors_only_target "0-25"
}

test_add_stops_on_inconclusive() {
  local mode
  for mode in timeout auth network; do
    setup_catalog
    create_oc_mock submariner-0-25-abc123 "$NEW_QUAY" "$NEW_VERSION"
    create_skopeo_digest_mock "$OTHER_SHA=$mode"

    run_update --version "$NEW_VERSION" --snapshot submariner-0-25-abc123

    assert_stopped_without_changes "ADD $mode"
  done
}

test_update_stops_on_inconclusive() {
  setup_catalog
  create_oc_mock "$TEST_SNAPSHOT_21_ABC123" "$TEST_BUNDLE_QUAY_21_ABC123" "$TEST_VERSION_21_2"
  create_skopeo_digest_mock "$OTHER_SHA=auth"

  run_update --version "$TEST_VERSION_21_2" --snapshot "$TEST_SNAPSHOT_21_ABC123"

  assert_stopped_without_changes "UPDATE auth"
}

test_replace_stops_on_inconclusive() {
  setup_catalog
  create_oc_mock "$TEST_SNAPSHOT_21_DEF456" "$TEST_BUNDLE_QUAY_21_DEF456" "$TEST_VERSION_21_3"
  create_skopeo_digest_mock "$OTHER_SHA=timeout"

  run_update --version "$TEST_VERSION_21_3" --snapshot "$TEST_SNAPSHOT_21_DEF456" --replace "$TEST_VERSION_21_2"

  assert_stopped_without_changes "REPLACE timeout"
}

# The snapshot's quay.io image must not overwrite the conversion of the bundle
# being updated (see the comment in main about the order of these steps).
test_update_keeps_conversion_of_target_bundle() {
  setup_catalog
  create_oc_mock "$TEST_SNAPSHOT_21_ABC123" "$TEST_BUNDLE_QUAY_21_ABC123" "$TEST_VERSION_21_2"
  create_skopeo_digest_mock "$TEST_SHA_ABC123=released" "$OTHER_SHA=released"

  run_update --version "$TEST_VERSION_21_2" --snapshot "$TEST_SNAPSHOT_21_ABC123"

  assert_exit_code 0 "$RUN_CODE" "UPDATE succeeds"
  assert_equals "$TEST_BUNDLE_REGISTRY_ABC123" "$(get_bundle_image "$TEST_BUNDLE_NAME_21_2")" "Updated bundle ends on registry.redhat.io"
  assert_equals "$OTHER_PROD" "$(get_bundle_image "$OTHER_NAME")" "Other Y-stream stays converted"
  assert_mirrors_only_target "0-21"
}

test_update_keeps_unknown_target_bundle() {
  setup_catalog
  create_oc_mock "$TEST_SNAPSHOT_21_ABC123" "$TEST_BUNDLE_QUAY_21_ABC123" "$TEST_VERSION_21_2"
  create_skopeo_digest_mock "$TEST_SHA_ABC123=auth" "$OTHER_SHA=released"

  run_update --version "$TEST_VERSION_21_2" --snapshot "$TEST_SNAPSHOT_21_ABC123"

  assert_exit_code 0 "$RUN_CODE" "UPDATE succeeds"
  assert_equals "$TEST_BUNDLE_QUAY_21_ABC123" "$(get_bundle_image "$TEST_BUNDLE_NAME_21_2")" "Target bundle kept on quay.io, covered by mirrors"
  assert_mirrors_only_target "0-21"
}

setup_mock_bin_dir

run_tests "test_"

exit $((TESTS_FAILED > 0 ? 1 : 0))
