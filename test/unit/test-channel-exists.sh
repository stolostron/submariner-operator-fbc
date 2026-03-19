#!/bin/bash
#
# test-channel-exists.sh - Unit tests for channel query functions
#
# Tests channel_exists, get_channel_entry_count, and get_latest_channel_entry functions.
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Source functions under test
source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

#------------------------------------------------------------------------------
# Test Cases - channel_exists
#------------------------------------------------------------------------------

test_channel_exists_true() {
  setup_fixture
  channel_exists "stable-0.21"
  assert_exit_code 0 "Channel stable-0.21 exists"
  cleanup_fixture
}

test_channel_exists_false() {
  setup_fixture
  channel_exists "stable-0.99" || code=$?
  cleanup_fixture
  assert_exit_code 1 "$code" "Channel stable-0.99 does not exist"
}

test_channel_exists_no_file() {
  rm -f catalog-template.yaml
  channel_exists "stable-0.21" || code=$?
  assert_exit_code 1 "$code" "Missing catalog-template.yaml returns error"
}

#------------------------------------------------------------------------------
# Test Cases - get_channel_entry_count
#------------------------------------------------------------------------------

test_get_channel_entry_count_two_entries() {
  setup_fixture
  local count=$(get_channel_entry_count "stable-0.21")
  cleanup_fixture
  assert_equals "2" "$count" "Channel stable-0.21 has 2 entries"
}

test_get_channel_entry_count_empty_channel() {
  setup_fixture fixture-0-22-empty.yaml
  local count=$(get_channel_entry_count "stable-0.22")
  cleanup_fixture
  assert_equals "0" "$count" "Empty channel stable-0.22 has 0 entries"
}

#------------------------------------------------------------------------------
# Test Cases - get_latest_channel_entry
#------------------------------------------------------------------------------

test_get_latest_channel_entry_exists() {
  setup_fixture
  local latest=$(get_latest_channel_entry "stable-0.21")
  cleanup_fixture
  # Channel entries define upgrade path: [newest] → [older] → [oldest]
  # get_latest_channel_entry() returns the last element in the channel's entries array,
  # which represents the tail/oldest version in the upgrade path (v0.21.0)
  assert_equals "submariner.v0.21.0" "$latest" "Latest entry in stable-0.21 is v0.21.0"
}

test_get_latest_channel_entry_empty_channel() {
  setup_fixture fixture-0-22-empty.yaml
  local latest=$(get_latest_channel_entry "stable-0.22")
  cleanup_fixture
  assert_equals "" "$latest" "Empty channel returns empty string (not 'null')"
}

test_get_latest_channel_entry_not_exists() {
  setup_fixture
  local latest=$(get_latest_channel_entry "stable-0.99")
  cleanup_fixture
  assert_equals "" "$latest" "Non-existent channel returns empty string"
}

#------------------------------------------------------------------------------
# Run Tests
#------------------------------------------------------------------------------

run_tests "test_*"
