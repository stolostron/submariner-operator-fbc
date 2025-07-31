#!/bin/bash

set -e

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
    name: submariner
    schema: olm.package
  - name: alpha-0.21
    package: submariner
    schema: olm.channel
    entries:
      - name: submariner.v0.21.0-rc0
        skipRange: '>=0.4.0 <0.21.0-rc0'
EOF

cp "${TEST_CATALOG_TEMPLATE}" "${ORIGINAL_CATALOG_TEMPLATE}"

# Test data
TEST_BUNDLE_IMAGE="test-registry/test-bundle:v0.0.1"
TEST_BUNDLE_VERSION="v0.0.1"
TEST_BUNDLE_CHANNELS="alpha,beta"

# Run the script
echo "Testing add-bundle-to-template.sh..."
./scripts/add-bundle-to-template.sh \
  "${TEST_CATALOG_TEMPLATE}" \
  "${TEST_BUNDLE_IMAGE}" \
  "${TEST_BUNDLE_VERSION}" \
  "${TEST_BUNDLE_CHANNELS}"

# Verification

# Check if the bundle entry was added
if ! yq '.entries[] | select(.image == "'""${TEST_BUNDLE_IMAGE}""'")' "${TEST_CATALOG_TEMPLATE}" > /dev/null; then
  echo "Test failed: Bundle entry not found in ${TEST_CATALOG_TEMPLATE}"
  exit 1
fi

# Check if the bundle was added to the alpha channel
if ! yq '.entries[] | select(.schema == "olm.channel") | select(.name == "alpha") | .entries[] | select(.name == "submariner.'"${TEST_BUNDLE_VERSION}"'")' "${TEST_CATALOG_TEMPLATE}" > /dev/null; then
  echo "Test failed: Bundle not found in alpha channel entries."
  exit 1
fi

# Check if the beta channel was created and bundle added
if ! yq '.entries[] | select(.schema == "olm.channel") | select(.name == "beta") | .entries[] | select(.name == "submariner.'"${TEST_BUNDLE_VERSION}"'")' "${TEST_CATALOG_TEMPLATE}" > /dev/null; then
  echo "Test failed: Beta channel not created or bundle not found in beta channel entries."
  exit 1
fi

echo "Test passed: add-bundle-to-template.sh worked as expected."

# Cleanup
rm "${TEST_CATALOG_TEMPLATE}"
rm "${ORIGINAL_CATALOG_TEMPLATE}"
