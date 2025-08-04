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

echo "--> Rendering catalog templates..."
./scripts/render-catalog.sh

echo "--> Formatting YAML files..."
./scripts/format-yaml.sh

echo "--> Build complete."

echo "--> Cleaning up intermediate catalog templates..."
rm -f catalog-template-4-*.yaml

echo "
##################################################"
echo "## Build Summary"
echo "##################################################"
echo "The following catalog directories were generated:"
for catalog_dir in catalog-*/; do
  find "${catalog_dir}" -print
  echo
done
