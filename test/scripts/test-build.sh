#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

echo "--> Validating existing catalogs (skipping rebuild)..."
echo "    Note: test-build.sh now validates existing catalogs instead of rebuilding"
echo "    to avoid registry.redhat.io rate limiting issues when pulling 24+ bundles."
echo ""

# Check that the expected number of catalog directories exist
num_catalogs=$(ls -d catalog-4-*/ 2>/dev/null | wc -l)
if [[ "${num_catalogs}" -eq 0 ]]; then
  echo "Error: No catalog directories found."
  echo "Run 'make build-catalogs' first to generate catalogs."
  exit 1
fi
echo "  ✓ Found ${num_catalogs} catalog directories"

# Validate each catalog with opm
echo "--> Running opm validate on each catalog..."
failed=0
for catalog_dir in catalog-4-*/; do
  catalog_name=$(basename "$catalog_dir")
  if ./bin/opm validate "$catalog_dir" > /dev/null 2>&1; then
    echo "  ✓ ${catalog_name}: valid"
  else
    echo "  ✗ ${catalog_name}: FAILED validation"
    failed=$((failed + 1))
  fi
done

if [ $failed -gt 0 ]; then
  echo ""
  echo "Error: $failed catalog(s) failed opm validation"
  exit 1
fi

echo ""
echo "  [SUCCESS] All ${num_catalogs} catalogs are valid"
