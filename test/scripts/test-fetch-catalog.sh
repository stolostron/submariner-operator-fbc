#!/bin/bash

set -euo pipefail
# shellcheck source=test/lib/isolate.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"

if [[ "${SKIP_AUTH_TESTS:-false}" = "true" ]]; then
  echo "Skipping test-fetch-catalog.sh as SKIP_AUTH_TESTS is set to true."
  exit 0
fi

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

OUTPUT_DIR="extracted-catalogs"
mkdir -p "${OUTPUT_DIR}"

echo "--> Running fetch-catalog-containerized.sh script..."
./scripts/fetch-catalog-containerized.sh 4.19 submariner

# Move the generated YAML to the output directory
mv submariner-catalog-config-4.19.yaml "${OUTPUT_DIR}/"

echo "--> Verifying output..."

# Check that the catalog file was created in the output directory
if [[ ! -f "${OUTPUT_DIR}/submariner-catalog-config-4.19.yaml" ]]; then
  echo "Error: submariner-catalog-config-4.19.yaml was not generated in ${OUTPUT_DIR}."
  exit 1
fi
echo "  [SUCCESS] submariner-catalog-config-4.19.yaml was generated in ${OUTPUT_DIR}."

# A merely existing output file is insufficient after an upstream command fails.
catalog="$OUTPUT_DIR/submariner-catalog-config-4.19.yaml"
yq -e '.entries[] | select(.schema == "olm.package" and .name == "submariner")' "$catalog" >/dev/null
yq -e '[.entries[] | select(.schema == "olm.bundle")] | length > 0' "$catalog" >/dev/null
DEFAULT_CHANNEL=$(yq '.entries[] | select(.schema == "olm.package").defaultChannel' "$catalog")
export DEFAULT_CHANNEL
yq -e '.entries[] | select(.schema == "olm.channel" and .name == strenv(DEFAULT_CHANNEL)) | .entries | length > 0' "$catalog" >/dev/null
echo 'Authenticated catalog fetch has the expected package, bundles, and default channel.'
