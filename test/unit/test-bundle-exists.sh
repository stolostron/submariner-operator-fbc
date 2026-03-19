#!/bin/bash
#
# test-bundle-exists.sh - Unit tests for bundle query functions
#
# Tests bundle_exists_in_template, get_bundle_entry, and get_bundle_image functions.
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Source functions under test
source "${REPO_ROOT_DIR}/scripts/lib/catalog-functions.sh"
source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

#------------------------------------------------------------------------------
# Test Cases - bundle_exists_in_template
#------------------------------------------------------------------------------

test_bundle_exists_true() {
  setup_fixture
  bundle_exists_in_template "submariner.v0.21.2"
  assert_exit_code 0 "Bundle v0.21.2 exists"
  cleanup_fixture
}

test_bundle_exists_false() {
  setup_fixture
  bundle_exists_in_template "submariner.v0.99.0" || code=$?
  cleanup_fixture
  assert_exit_code 1 "$code" "Bundle v0.99.0 does not exist"
}

test_bundle_exists_no_file() {
  rm -f catalog-template.yaml
  bundle_exists_in_template "submariner.v0.21.0" || code=$?
  assert_exit_code 1 "$code" "Missing catalog-template.yaml returns error"
}

#------------------------------------------------------------------------------
# Test Cases - get_bundle_entry
#------------------------------------------------------------------------------

test_get_bundle_entry_exists() {
  setup_fixture
  local entry=$(get_bundle_entry "submariner.v0.21.0")
  cleanup_fixture
  [ -n "$entry" ]
  assert_exit_code 0 "get_bundle_entry returns non-empty for existing bundle"
}

test_get_bundle_entry_not_exists() {
  setup_fixture
  local entry=$(get_bundle_entry "submariner.v0.99.0")
  cleanup_fixture
  assert_equals "" "$entry" "get_bundle_entry returns empty for non-existent bundle"
}

#------------------------------------------------------------------------------
# Test Cases - get_bundle_image
#------------------------------------------------------------------------------

test_get_bundle_image_exists() {
  setup_fixture
  local image=$(get_bundle_image "submariner.v0.21.0")
  cleanup_fixture
  local expected="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:7a23eb13e0197b4eab7a645ff18c1abd63a39234c55c0e19b8c1c39aa2fe6e99"
  assert_equals "$expected" "$image" "get_bundle_image returns correct image URL"
}

test_get_bundle_image_not_exists() {
  setup_fixture
  local image=$(get_bundle_image "submariner.v0.99.0")
  cleanup_fixture
  assert_equals "" "$image" "get_bundle_image returns empty for non-existent bundle"
}

#------------------------------------------------------------------------------
# Run Tests
#------------------------------------------------------------------------------

run_tests "test_*"
