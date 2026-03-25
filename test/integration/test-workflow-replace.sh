#!/bin/bash
# test-workflow-replace.sh - Integration test for REPLACE scenario
#
# Scenario: Skip broken version by replacing with new version (update skipRange)
# Why: Prevents users from installing broken versions while preserving upgrade continuity

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/mock-commands.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== Integration Test: REPLACE Workflow ==="
echo ""

validate_integration_test_prerequisites || exit 1
initialize_integration_test

create_oc_mock "$TEST_SNAPSHOT_21_DEF456" "$TEST_BUNDLE_QUAY_21_DEF456"

setup_mock_bin_dir
create_skopeo_mock 1 "submariner-bundle-$TEST_Y_STREAM_21"

echo "Running REPLACE workflow: $TEST_VERSION_21_3 replaces $TEST_VERSION_21_2..."
echo ""

if ! bundle_exists_in_template "$TEST_BUNDLE_NAME_21_2"; then
  echo "ERROR: Old version $TEST_VERSION_21_2 doesn't exist!"
  exit 1
fi
echo "✓ Old version $TEST_VERSION_21_2 exists"

if bundle_exists_in_template "$TEST_BUNDLE_NAME_21_3"; then
  echo "ERROR: New version $TEST_VERSION_21_3 already exists!"
  exit 1
fi
echo "✓ New version $TEST_VERSION_21_3 doesn't exist yet"
echo ""

export SKIP_BUILD_CATALOGS=true
./scripts/update-bundle.sh --version "$TEST_VERSION_21_3" --snapshot "$TEST_SNAPSHOT_21_DEF456" --replace "$TEST_VERSION_21_2"

echo ""
echo "Verifying REPLACE workflow..."
echo ""

OLD_BUNDLE=$(get_bundle_entry_from_catalog "$TEST_BUNDLE_NAME_21_2")
NEW_BUNDLE=$(get_bundle_entry_from_catalog "$TEST_BUNDLE_NAME_21_3")

assert_empty "$OLD_BUNDLE" "Old bundle v$TEST_VERSION_21_2 removed from template"
assert_non_empty "$NEW_BUNDLE" "New bundle v$TEST_VERSION_21_3 added to template"

NEW_CHANNEL_ENTRY=$(get_channel_entry_for_bundle "$TEST_CHANNEL_21" "$TEST_BUNDLE_NAME_21_3")
SKIP_RANGE=$(get_yq_field "$NEW_CHANNEL_ENTRY" '.skipRange')
REPLACES=$(get_yq_field "$NEW_CHANNEL_ENTRY" '.replaces')

assert_equals "$TEST_SKIPRANGE_20_21_3" "$SKIP_RANGE" "skipRange excludes v$TEST_VERSION_21_2"
assert_equals "$TEST_BUNDLE_NAME_21_0" "$REPLACES" "Replaces field unchanged (inherits from v$TEST_VERSION_21_2)"

print_test_summary "REPLACE workflow" || exit 1
