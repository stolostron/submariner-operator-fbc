#!/bin/bash

set -euo pipefail

if [[ "${SKIP_AUTH_TESTS:-false}" = "true" ]]; then
  echo "Skipping test-fetch-catalog.sh as SKIP_AUTH_TESTS is set to true."
  exit 0
fi

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

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
