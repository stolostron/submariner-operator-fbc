#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Ensure cleanup happens on exit
trap './build/cleanup-generated-files.sh' EXIT

echo "--> Cleaning up before test..."
./build/cleanup-generated-files.sh

echo "--> Running build script..."
./build/build.sh

echo "--> Verifying build output..."

# Check that the expected number of catalog-template files were created
num_templates=$(ls catalog-template-4-*.yaml | wc -l)
if [[ "${num_templates}" -eq 0 ]]; then
  echo "Error: No catalog-template files were generated."
  exit 1
fi
echo "  [SUCCESS] Found ${num_templates} catalog-template files."

# Check that the expected number of catalog directories were created
num_catalogs=$(ls -d catalog-4-*/ | wc -l)
if [[ "${num_catalogs}" -eq 0 ]]; then
  echo "Error: No catalog directories were generated."
  exit 1
fi
echo "  [SUCCESS] Found ${num_catalogs} catalog directories."
