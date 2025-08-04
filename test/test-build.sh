#!/bin/bash

set -euo pipefail

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"



echo "--> Running build script..."
./build/build.sh

echo "--> Verifying build output..."

# Check that the expected number of catalog directories were created
num_catalogs=$(ls -d catalog-4-*/ | wc -l)
if [[ "${num_catalogs}" -eq 0 ]]; then
  echo "Error: No catalog directories were generated."
  exit 1
fi
echo "  [SUCCESS] Found ${num_catalogs} catalog directories."
