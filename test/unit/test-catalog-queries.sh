#!/bin/bash
# test-catalog-queries.sh - Unit tests for catalog query functions

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"

# Test data for bundle_exists_in_template: bundle_name|expected_code|setup|description
bundle_exists_cases=(
  "$TEST_BUNDLE_NAME_21_2|0|fixture|Bundle v0.21.2 exists"
  "$TEST_BUNDLE_NAME_NONEXISTENT|1|fixture|Bundle v0.99.0 does not exist"
  "$TEST_BUNDLE_NAME_21_0|1|no_file|Missing catalog-template.yaml returns error"
)

test_bundle_exists_table_driven() {
  local failed=0

  for test_case in "${bundle_exists_cases[@]}"; do
    IFS='|' read -r bundle expected_code setup description <<< "$test_case"

    if [ "$setup" = "fixture" ]; then
      setup_fixture
    else
      rm -f catalog-template.yaml
    fi

    local actual_code=0
    bundle_exists_in_template "$bundle" || actual_code=$?

    [ "$setup" = "fixture" ] && cleanup_fixture

    assert_exit_code "$expected_code" "$actual_code" "$description" || failed=$((failed + 1))
  done

  return $failed
}

# Test data for get_bundle_entry: bundle_name|has_result|description
bundle_entry_cases=(
  "$TEST_BUNDLE_NAME_21_0|1|get_bundle_entry returns non-empty for existing bundle"
  "$TEST_BUNDLE_NAME_NONEXISTENT|0|get_bundle_entry returns empty for non-existent bundle"
)

test_get_bundle_entry_table_driven() {
  local failed=0

  for test_case in "${bundle_entry_cases[@]}"; do
    IFS='|' read -r bundle has_result description <<< "$test_case"

    setup_fixture
    local entry
    entry=$(get_bundle_entry "$bundle")
    cleanup_fixture

    if [ "$has_result" -eq 1 ]; then
      assert_non_empty "$entry" "$description" || failed=$((failed + 1))
    else
      assert_empty "$entry" "$description" || failed=$((failed + 1))
    fi
  done

  return $failed
}

# Test data for get_bundle_image: bundle_name|expected_image|description
bundle_image_cases=(
  "$TEST_BUNDLE_NAME_21_0|$TEST_BUNDLE_REGISTRY_REAL_21_0|get_bundle_image returns correct image URL"
  "$TEST_BUNDLE_NAME_NONEXISTENT||get_bundle_image returns empty for non-existent bundle"
)

test_get_bundle_image_table_driven() {
  local failed=0

  for test_case in "${bundle_image_cases[@]}"; do
    IFS='|' read -r bundle expected description <<< "$test_case"

    setup_fixture
    local actual
    actual=$(get_bundle_image "$bundle")
    cleanup_fixture

    assert_equals "$expected" "$actual" "$description" || failed=$((failed + 1))
  done

  return $failed
}

# Test data for channel_exists: channel_name|expected_code|setup|description
channel_exists_cases=(
  "$TEST_CHANNEL_21|0|fixture|Channel stable-0.21 exists"
  "$TEST_CHANNEL_NONEXISTENT|1|fixture|Channel stable-0.99 does not exist"
  "$TEST_CHANNEL_21|1|no_file|Missing catalog-template.yaml returns error"
)

test_channel_exists_table_driven() {
  local failed=0

  for test_case in "${channel_exists_cases[@]}"; do
    IFS='|' read -r channel expected_code setup description <<< "$test_case"

    if [ "$setup" = "fixture" ]; then
      setup_fixture
    else
      rm -f catalog-template.yaml
    fi

    local actual_code=0
    channel_exists "$channel" || actual_code=$?

    [ "$setup" = "fixture" ] && cleanup_fixture

    assert_exit_code "$expected_code" "$actual_code" "$description" || failed=$((failed + 1))
  done

  return $failed
}

# Test data for get_channel_entry_count: channel_name|fixture|expected_count|description
channel_entry_count_cases=(
  "$TEST_CHANNEL_21|fixture-0-21.yaml|2|Channel stable-0.21 has 2 entries"
  "$TEST_CHANNEL_22|fixture-0-21.yaml:add-empty-0-22|0|Empty channel stable-0.22 has 0 entries"
)

test_get_channel_entry_count_table_driven() {
  local failed=0

  for test_case in "${channel_entry_count_cases[@]}"; do
    IFS='|' read -r channel fixture expected description <<< "$test_case"

    setup_fixture "$fixture"
    local actual
    actual=$(get_channel_entry_count "$channel")
    cleanup_fixture

    assert_equals "$expected" "$actual" "$description" || failed=$((failed + 1))
  done

  return $failed
}

# Test data for get_latest_channel_entry: channel_name|fixture|expected_entry|description
channel_latest_entry_cases=(
  "$TEST_CHANNEL_21|fixture-0-21.yaml|$TEST_BUNDLE_NAME_21_0|Latest entry in stable-0.21 is v0.21.0"
  "$TEST_CHANNEL_22|fixture-0-21.yaml:add-empty-0-22||Empty channel returns empty string (not 'null')"
  "$TEST_CHANNEL_NONEXISTENT|fixture-0-21.yaml||Non-existent channel returns empty string"
)

test_get_latest_channel_entry_table_driven() {
  local failed=0

  for test_case in "${channel_latest_entry_cases[@]}"; do
    IFS='|' read -r channel fixture expected description <<< "$test_case"

    setup_fixture "$fixture"
    local actual
    actual=$(get_latest_channel_entry "$channel")
    cleanup_fixture

    assert_equals "$expected" "$actual" "$description" || failed=$((failed + 1))
  done

  return $failed
}

#------------------------------------------------------------------------------
run_tests "test_*"
