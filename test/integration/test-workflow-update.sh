#!/bin/bash
# test-workflow-update.sh - Integration test for UPDATE scenario
#
# Scenario: Konflux rebuilds existing bundle with new SHA (same version)
# Why: FBC must track latest bundle SHA (~40% of updates)

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/mock-commands.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== Integration Test: UPDATE Workflow ==="
echo ""

validate_integration_test_prerequisites || exit 1
initialize_integration_test

# Create oc mock for UPDATE scenario
create_oc_mock "$TEST_SNAPSHOT_21_ABC123" "$TEST_BUNDLE_QUAY_21_ABC123"

setup_mock_bin_dir
create_skopeo_mock 0

echo "Running UPDATE workflow for version $TEST_VERSION_21_2..."
echo ""

# Capture BEFORE state
BUNDLE_BEFORE=$(get_bundle_entry_from_catalog "$TEST_BUNDLE_NAME_21_2")
ORIGINAL_SHA=$(extract_sha "$(get_yq_field "$BUNDLE_BEFORE" '.image')")
CHANNEL_BEFORE=$(get_channel_entry_for_bundle "$TEST_CHANNEL_21" "$TEST_BUNDLE_NAME_21_2")
REPLACES_BEFORE=$(get_yq_field "$CHANNEL_BEFORE" '.replaces')
SKIP_RANGE_BEFORE=$(get_yq_field "$CHANNEL_BEFORE" '.skipRange')

echo "Original SHA: ${ORIGINAL_SHA:0:12}..."
echo "New SHA:      ${TEST_SHA_ABC123:0:12}..."
echo ""

export SKIP_BUILD_CATALOGS=true
./scripts/update-bundle.sh --version "$TEST_VERSION_21_2" --snapshot "$TEST_SNAPSHOT_21_ABC123"

echo ""
echo "Verifying UPDATE workflow..."
echo ""

BUNDLE_AFTER=$(get_bundle_entry_from_catalog "$TEST_BUNDLE_NAME_21_2")
NEW_SHA=$(extract_sha "$(get_yq_field "$BUNDLE_AFTER" '.image')")
assert_equals "$TEST_SHA_ABC123" "$NEW_SHA" "Bundle SHA updated in template"

CHANNEL_AFTER=$(get_channel_entry_for_bundle "$TEST_CHANNEL_21" "$TEST_BUNDLE_NAME_21_2")
REPLACES_AFTER=$(get_yq_field "$CHANNEL_AFTER" '.replaces')
SKIP_RANGE_AFTER=$(get_yq_field "$CHANNEL_AFTER" '.skipRange')

assert_equals "$REPLACES_BEFORE" "$REPLACES_AFTER" "Channel replaces field unchanged"
assert_equals "$SKIP_RANGE_BEFORE" "$SKIP_RANGE_AFTER" "Channel skipRange unchanged"

print_test_summary "UPDATE workflow" || exit 1
