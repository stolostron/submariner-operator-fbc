#!/bin/bash

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

TEST_CATALOG_TEMPLATE="test_catalog_template.yaml"
ORIGINAL_CATALOG_TEMPLATE="original_catalog_template.yaml"

# Setup: Create a dummy catalog-template.yaml
cat <<EOF > "${TEST_CATALOG_TEMPLATE}"
---
schema: olm.template.basic
entries:
  - defaultChannel: stable
    icon:
      base64data: somebase64data
      mediatype: image/svg+xml
    name: submariner-product
    schema: olm.package
  - name: alpha-0.21
    package: submariner-product
    schema: olm.channel
    entries:
      - name: submariner-product.v0.21.0-rc0
        skipRange: '>=0.4.0 <0.21.0-rc0'
EOF

cp "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"

# Test data
TEST_BUNDLE_IMAGE="test-registry/test-bundle:v0.0.1"
TEST_BUNDLE_NAME="test-product.v0.0.1-abcdefg"
TEST_BUNDLE_VERSION="v0.0.1"
TEST_BUNDLE_CHANNELS="alpha,beta"

# Run the add script
echo "Testing add-bundle-to-template.sh..."
./build/add-bundle-to-template.sh \
  "${TEST_CATALOG_TEMPLATE}" \
  "${TEST_BUNDLE_IMAGE}" \
  "${TEST_BUNDLE_NAME}" \
  "${TEST_BUNDLE_VERSION}" \
  "${TEST_BUNDLE_CHANNELS}"

# Run the remove script
echo "Testing remove-bundle.sh..."
./build/remove-bundle.sh \
  "${TEST_CATALOG_TEMPLATE}" \
  "${TEST_BUNDLE_VERSION}"

# Verification

echo "--- Original --- "
cat "${ORIGINAL_CATALOG_TEMPLATE}"

echo "--- After --- "
cat "${TEST_CATALOG_TEMPLATE}"

if ! diff -q "${ORIGINAL_CATALOG_TEMPLATE}" "${TEST_CATALOG_TEMPLATE}"; then
  echo "Test failed: The catalog template was modified."
  exit 1
fi

echo "Test passed: add and remove bundle worked as expected."

# Cleanup
rm "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"
