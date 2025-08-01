#!/bin/bash

set -e

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

TEST_CATALOG_TEMPLATE="test_catalog_template_add_build.yaml"
ORIGINAL_CATALOG_TEMPLATE="original_catalog_template_add_build.yaml"

# Setup: Create a dummy catalog-template.yaml
cp catalog-template.yaml "${TEST_CATALOG_TEMPLATE}"
cp "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"

# Test data
TEST_BUNDLE_IMAGE="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:bad7ce0c4a3edcb12dc3adf3e4165bd57631c06bc81ed9b507377b12e73f905c"

echo "### Testing add-bundle.sh and build.sh workflow ###"

# Capture initial git status
git_status_before=$(git status --porcelain)

# 1. Add the bundle
echo "  Adding bundle to ${TEST_CATALOG_TEMPLATE}..."
./build/add-bundle.sh "${TEST_BUNDLE_IMAGE}"

# 2. Build the catalog
echo "  Building catalog with the added bundle..."
./build/build.sh

# Capture final git status
git_status_after=$(git status --porcelain)

# 3. Verify sanity of results

# Verify new files were created
new_files=$(git diff --name-only --diff-filter=A)

if ! echo "${new_files}" | grep -q "catalog-4-14/bundles/bundle-v0.21.0.yaml"; then
  echo "Test failed: Expected bundle file not found in new files."
  exit 1
fi

if ! echo "${new_files}" | grep -q "catalog-4-14/package.yaml"; then
  echo "Test failed: Expected package file not found in new files."
  exit 1
fi

if ! echo "${new_files}" | grep -q "catalog-4-14/channels/channel-stable-0.21.yaml"; then
  echo "Test failed: Expected channel file not found in new files."
  exit 1
fi

echo "Test passed: Add bundle and build catalog workflow worked as expected."

# Cleanup
rm "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"
rm -rf catalog-4-14 catalog-4-15 catalog-4-16 catalog-4-17 catalog-4-18 catalog-4-19
