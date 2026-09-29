#!/bin/bash

set -euo pipefail
# shellcheck source=test/lib/isolate.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

echo "--> Validating existing catalogs (skipping rebuild)..."
echo "    Note: test-build.sh now validates existing catalogs instead of rebuilding"
echo "    to avoid registry.redhat.io rate limiting issues when pulling 24+ bundles."
echo ""

mapfile -t versions < <(jq -r 'keys[] | gsub("\\."; "-")' drop-versions.json)
num_catalogs=${#versions[@]}
[ "$num_catalogs" -gt 0 ] || exit 1
for version in "${versions[@]}"; do
  [ -d "catalog-$version" ] || { echo "Missing configured catalog-$version" >&2; exit 1; }
done

# Validate each catalog with opm
echo "--> Running opm validate on each catalog..."
failed=0
for version in "${versions[@]}"; do
  catalog_dir="catalog-$version"
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
