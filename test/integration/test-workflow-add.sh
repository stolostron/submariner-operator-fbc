#!/bin/bash
# test-workflow-add.sh - Integration test for ADD scenario
#
# Scenario: First release of new Y-stream version (creates channel + bundle)
# Why: New versions need proper skipRange and upgrade paths

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/mock-commands.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== Integration Test: ADD Workflow ==="
echo ""

validate_integration_test_prerequisites || exit 1
initialize_integration_test

create_oc_mock "$TEST_SNAPSHOT_24_XYZ789" "$TEST_BUNDLE_QUAY_24_FEDCBA"

setup_mock_bin_dir
create_skopeo_mock 1 "submariner-bundle-$TEST_Y_STREAM_24"

echo "Running ADD workflow for new version $TEST_VERSION_24_0..."
echo ""

if bundle_exists_in_template "$TEST_BUNDLE_NAME_24_0"; then
  echo "ERROR: Version $TEST_VERSION_24_0 already exists in catalog!"
  exit 1
fi

echo "✓ Confirmed $TEST_VERSION_24_0 doesn't exist yet"
echo ""

export SKIP_BUILD_CATALOGS=true
./scripts/update-bundle.sh --version "$TEST_VERSION_24_0" --snapshot "$TEST_SNAPSHOT_24_XYZ789"

echo ""
echo "Verifying ADD workflow..."
echo ""

BUNDLE_ENTRY=$(get_bundle_entry_from_catalog "$TEST_BUNDLE_NAME_24_0")
assert_non_empty "$BUNDLE_ENTRY" "Bundle entry added to catalog"

BUNDLE_IMAGE=$(get_yq_field "$BUNDLE_ENTRY" '.image')
assert_equals "$TEST_BUNDLE_QUAY_24_FEDCBA" "$BUNDLE_IMAGE" "Bundle image SHA correct"

if ! channel_exists "$TEST_CHANNEL_24"; then
  echo "ERROR: Channel $TEST_CHANNEL_24 was not created"
  exit 1
fi
echo "✓ New channel $TEST_CHANNEL_24 created"

CHANNEL_ENTRY=$(get_channel_entry_for_bundle "$TEST_CHANNEL_24" "$TEST_BUNDLE_NAME_24_0")
ENTRY_NAME=$(get_yq_field "$CHANNEL_ENTRY" '.name')
assert_equals "$TEST_BUNDLE_NAME_24_0" "$ENTRY_NAME" "Bundle added as first entry in channel"

REPLACES=$(get_yq_field "$CHANNEL_ENTRY" '.replaces')
assert_equals "null" "$REPLACES" "First entry has no replaces field"

SKIP_RANGE=$(get_yq_field "$CHANNEL_ENTRY" '.skipRange')
assert_equals "$TEST_SKIPRANGE_18_24_0" "$SKIP_RANGE" "First entry skipRange correct"

DEFAULT_CHANNEL=$(yq eval '.entries[] | select(.schema == "olm.package") | .defaultChannel' catalog-template.yaml)
assert_equals "$TEST_CHANNEL_24" "$DEFAULT_CHANNEL" "defaultChannel updated to $TEST_CHANNEL_24"

echo ""
echo "Validating real production catalogs..."
validate_catalog "catalog-4-16"
echo "✓ Real catalogs validated successfully"

print_test_summary "ADD workflow" || exit 1
