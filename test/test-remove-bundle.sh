#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

TEST_CATALOG_TEMPLATE="test_catalog_template.yaml"

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
  - image: test-registry/test-bundle:v0.0.1
    name: submariner.v0.0.1
    schema: olm.bundle
EOF

# Test data
TEST_BUNDLE_VERSION="v0.0.1"

echo "--- Before --- "
cat "${TEST_CATALOG_TEMPLATE}"

# Run the script
echo "Testing remove-bundle.sh..."
./scripts/remove-bundle.sh \
  "${TEST_CATALOG_TEMPLATE}" \
  "${TEST_BUNDLE_VERSION}"

# Verification

echo "--- After --- "
cat "${TEST_CATALOG_TEMPLATE}"

# Check if the bundle entry was removed
if yq e '.entries[] | select(.schema == "olm.bundle")' "${TEST_CATALOG_TEMPLATE}" | grep -q ${TEST_BUNDLE_VERSION}; then
  echo "Test failed: Bundle entry not removed from ${TEST_CATALOG_TEMPLATE}"
  exit 1
fi

echo "Test passed: remove-bundle.sh worked as expected."

# Cleanup
rm "${TEST_CATALOG_TEMPLATE}"
