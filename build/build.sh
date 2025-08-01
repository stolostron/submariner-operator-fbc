#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Clean up previous build artifacts
echo "--> Cleaning up previous build artifacts (catalog-*/ directories)..."
rm -rf catalog-*/

echo "--> Generating catalog template..."
./scripts/generate-catalog-template.sh

echo "--> Rendering catalog templates using the opm container..."
./scripts/render-catalog-containerized.sh

echo "--> Cleaning up temporary files..."
./scripts/cleanup-generated-files.sh

echo "--> Build complete."

echo "
##################################################"
echo "## Build Summary"
echo "##################################################"
echo "The following catalog directories were generated:"
for catalog_dir in catalog-*/; do
  find "${catalog_dir}" -print
  echo
done
