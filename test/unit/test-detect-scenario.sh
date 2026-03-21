#!/bin/bash
#
# test-detect-scenario.sh - Unit tests for scenario detection logic
#
# Tests the core detection logic using catalog query functions.
# Note: Full integration testing of detect_scenario() requires fixtures and mocking.
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Source functions under test
source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

#------------------------------------------------------------------------------
# Setup
#------------------------------------------------------------------------------

setup_0_21_fixture() {
  cp "${REPO_ROOT_DIR}/test/fixtures/fixture-0-21.yaml" catalog-template.yaml
}

setup_empty_0_22_fixture() {
  cp "${REPO_ROOT_DIR}/test/fixtures/fixture-0-22-empty.yaml" catalog-template.yaml
}

cleanup_fixture() {
  rm -f catalog-template.yaml
}

#------------------------------------------------------------------------------
# Helper function to detect scenario based on catalog state
#------------------------------------------------------------------------------

detect_scenario_logic() {
  local bundle_name="$1"
  local channel_name="$2"
  local replace_version="${3:-}"

  local bundle_exists=""
  local channel_bundle_exists=""

  if bundle_exists_in_template "$bundle_name"; then
    bundle_exists="yes"
  fi

  local channel_entry=$(yq eval ".entries[] | select(.schema == \"olm.channel\" and .name == \"$channel_name\") | .entries[] | select(.name == \"$bundle_name\") | .name" catalog-template.yaml)
  if [ -n "$channel_entry" ]; then
    channel_bundle_exists="yes"
  fi

  if [ -n "$replace_version" ]; then
    local old_bundle="submariner.v${replace_version}"
    if ! bundle_exists_in_template "$old_bundle"; then
      echo "ERROR"
      return 1
    fi
    if [ -n "$bundle_exists" ]; then
      echo "ERROR"
      return 1
    fi
    echo "REPLACE"
  elif [ -z "$bundle_exists" ] && [ -z "$channel_bundle_exists" ]; then
    echo "ADD"
  elif [ -n "$bundle_exists" ] && [ -n "$channel_bundle_exists" ]; then
    echo "UPDATE"
  else
    echo "ERROR"
    return 1
  fi
}

#------------------------------------------------------------------------------
# Test Cases - ADD Scenario
#------------------------------------------------------------------------------

test_scenario_add_new_version() {
  setup_0_21_fixture
  local scenario=$(detect_scenario_logic "submariner.v0.22.0" "stable-0.22" "")
  cleanup_fixture
  assert_equals "ADD" "$scenario" "Detect ADD for new version not in catalog"
}

#------------------------------------------------------------------------------
# Test Cases - UPDATE Scenario
#------------------------------------------------------------------------------

test_scenario_update_existing_version() {
  setup_0_21_fixture
  local scenario=$(detect_scenario_logic "submariner.v0.21.2" "stable-0.21" "")
  cleanup_fixture
  assert_equals "UPDATE" "$scenario" "Detect UPDATE for existing version in catalog and channel"
}

#------------------------------------------------------------------------------
# Test Cases - REPLACE Scenario
#------------------------------------------------------------------------------

test_scenario_replace_valid() {
  setup_0_21_fixture
  local scenario=$(detect_scenario_logic "submariner.v0.21.3" "stable-0.21" "0.21.2")
  cleanup_fixture
  assert_equals "REPLACE" "$scenario" "Detect REPLACE when old version exists and new doesn't"
}

test_scenario_replace_old_not_exists() {
  setup_0_21_fixture
  local exit_code=0
  detect_scenario_logic "submariner.v0.21.3" "stable-0.21" "0.21.99" 2>/dev/null || exit_code=$?
  cleanup_fixture
  assert_exit_code 1 "$exit_code" "REPLACE fails when old version doesn't exist"
}

test_scenario_replace_new_exists() {
  setup_0_21_fixture
  local exit_code=0
  detect_scenario_logic "submariner.v0.21.2" "stable-0.21" "0.21.0" 2>/dev/null || exit_code=$?
  cleanup_fixture
  assert_exit_code 1 "$exit_code" "REPLACE fails when new version already exists"
}

#------------------------------------------------------------------------------
# Test Cases - ERROR Scenarios
#------------------------------------------------------------------------------

test_scenario_error_bundle_exists_but_not_in_channel() {
  setup_0_21_fixture
  yq eval '.entries += [{"name": "submariner.v0.21.5", "image": "test", "schema": "olm.bundle"}]' -i catalog-template.yaml
  local exit_code=0
  detect_scenario_logic "submariner.v0.21.5" "stable-0.21" "" 2>/dev/null || exit_code=$?
  cleanup_fixture
  assert_exit_code 1 "$exit_code" "ERROR for inconsistent state (bundle exists but not in channel)"
}

#------------------------------------------------------------------------------
# Run Tests
#------------------------------------------------------------------------------

run_tests "test_scenario_*"
