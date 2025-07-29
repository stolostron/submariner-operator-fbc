#!/bin/bash

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

TEST_CATALOG_TEMPLATE="test_catalog_template_advanced.yaml"
ORIGINAL_CATALOG_TEMPLATE="original_catalog_template_advanced.yaml"

# Setup: Create a dummy catalog-template.yaml with an existing bundle in the alpha channel
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
  - name: alpha
    package: submariner-product
    schema: olm.channel
    entries:
      - name: submariner-product.v0.20.0
        skipRange: '>=0.4.0 <0.20.0'
  - image: test-registry/test-bundle:v0.20.0
    name: submariner-product.v0.20.0
    schema: olm.bundle
EOF

cp "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"

# Test data for a new bundle to be added to the existing alpha channel
TEST_BUNDLE_IMAGE="test-registry/test-bundle:v0.21.0"
TEST_BUNDLE_NAME="submariner-product.v0.21.0"
TEST_BUNDLE_VERSION="v0.21.0"
TEST_BUNDLE_CHANNELS="alpha"

# --- Run the add script --- #
echo "### Testing add-bundle-to-template.sh (Advanced) ###"
./build/add-bundle-to-template.sh \
  "${TEST_CATALOG_TEMPLATE}" \
  "${TEST_BUNDLE_IMAGE}" \
  "${TEST_BUNDLE_NAME}" \
  "${TEST_BUNDLE_VERSION}" \
  "${TEST_BUNDLE_CHANNELS}"

echo "--- After Add --- "
cat "${TEST_CATALOG_TEMPLATE}"

# --- Run the remove script --- #
echo "### Testing remove-bundle.sh (Advanced) ###"
./build/remove-bundle.sh \
  "${TEST_CATALOG_TEMPLATE}" \
  "${TEST_BUNDLE_VERSION}"

# --- Verification --- #
echo "--- Original --- "
cat "${ORIGINAL_CATALOG_TEMPLATE}"

echo "--- After Remove --- "
cat "${TEST_CATALOG_TEMPLATE}"

# Verify that the file is identical to the original
if ! diff -q "${ORIGINAL_CATALOG_TEMPLATE}" "${TEST_CATALOG_TEMPLATE}"; then
  echo "Test failed: The catalog template was modified."
  diff "${ORIGINAL_CATALOG_TEMPLATE}" "${TEST_CATALOG_TEMPLATE}"
  exit 1
fi

echo "Test passed: Advanced add and remove bundle worked as expected."

# Cleanup
rm "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"
