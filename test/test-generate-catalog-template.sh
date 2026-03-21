#!/bin/bash

set -euo pipefail

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Run the script
./scripts/generate-catalog-template.sh

# Verify all 8 OCP version templates were created (4-14 through 4-21)
EXPECTED_VERSIONS=(4-14 4-15 4-16 4-17 4-18 4-19 4-20 4-21)
FAILED=0

for VERSION in "${EXPECTED_VERSIONS[@]}"; do
  if [ ! -f "catalog-template-${VERSION}.yaml" ]; then
    echo "Test failed: catalog-template-${VERSION}.yaml was not created."
    FAILED=1
  fi
done

if [ $FAILED -eq 1 ]; then
  exit 1
fi

echo "Test passed: generate-catalog-template.sh created all 8 expected catalog templates (4-14 through 4-21)."

# Cleanup
rm catalog-template-*-*.yaml
