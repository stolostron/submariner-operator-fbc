#!/bin/bash

set -euo pipefail

./scripts/reset-test-environment.sh

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
TEST_BUNDLE_IMAGE="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:bad7ce0c4a3edcb12dc3adf3e4165bd57631c06bc81ed9b507377b12e73f905c"

# Run the script
echo "Testing add-bundle.sh..."
./build/add-bundle.sh "${TEST_BUNDLE_IMAGE}"

# Verification

# Check if the bundle entry was added
if ! yq '.entries[] | select(.image == "'""${TEST_BUNDLE_IMAGE}""'")' "${TEST_CATALOG_TEMPLATE}" > /dev/null; then
  echo "Test failed: Bundle entry not found in ${TEST_CATALOG_TEMPLATE}"
  exit 1
fi

if ! yq '.entries[] | select(.schema == "olm.channel") | select(.name == "stable-0.21") | .entries[] | select(.name == "submariner.v0.21.0-rc0")' "${TEST_CATALOG_TEMPLATE}" > /dev/null; then
  echo "Test failed: Bundle not found in stable-0.21 channel entries."
  exit 1
fi

echo "Test passed: add-bundle-to-template.sh worked as expected."

# Cleanup
rm "${TEST_CATALOG_TEMPLATE}"
rm "${ORIGINAL_CATALOG_TEMPLATE}"
