#!/bin/bash

set -e

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
    name: submariner
    schema: olm.package
  - name: alpha
    package: submariner
    schema: olm.channel
    entries:
      - name: submariner.v0.20.0
        skipRange: '>=0.4.0 <0.20.0'
  - image: test-registry/test-bundle:v0.20.0
    name: submariner.v0.20.0
    schema: olm.bundle
EOF

cp "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"

# Test data for a new bundle to be added to the existing alpha channel
TEST_BUNDLE_IMAGE="test-registry/test-bundle:v0.21.0"
TEST_BUNDLE_NAME="submariner.v0.21.0"
TEST_BUNDLE_VERSION="v0.21.0"
TEST_BUNDLE_CHANNELS="alpha"

# --- Run the add script --- #
echo "### Testing add-bundle-to-template.sh (Advanced) ###"
./scripts/add-bundle-to-template.sh \
  "${TEST_CATALOG_TEMPLATE}" \
  "${TEST_BUNDLE_IMAGE}" \
  "${TEST_BUNDLE_VERSION}" \
  "${TEST_BUNDLE_CHANNELS}"

echo "--- After Add --- "
cat "${TEST_CATALOG_TEMPLATE}"

# --- Verification --- #
# Verify that the new bundle was added correctly
if ! yq '.entries[] | select(.schema == "olm.bundle") | select(.name == "'"${TEST_BUNDLE_NAME}"'")' "${TEST_CATALOG_TEMPLATE}" > /dev/null; then
  echo "Test failed: New bundle entry not found in ${TEST_CATALOG_TEMPLATE}"
  exit 1
fi

if ! yq '.entries[] | select(.schema == "olm.channel") | select(.name == "alpha") | .entries[] | select(.name == "'"${TEST_BUNDLE_NAME}"'")' "${TEST_CATALOG_TEMPLATE}" > /dev/null; then
  echo "Test failed: New bundle not found in alpha channel entries."
  exit 1
fi

echo "Test passed: Advanced add bundle worked as expected."

# Cleanup
rm "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"
