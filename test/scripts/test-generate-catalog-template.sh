#!/bin/bash

set -euo pipefail
# shellcheck source=test/lib/isolate.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/isolate.sh"

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Setup cleanup trap to ensure files are removed even on failure
cleanup() {
  rm -f catalog-template-*-*.yaml 2>/dev/null || true
}
trap cleanup EXIT

# Run the script
./scripts/generate-catalog-template.sh

# Verify all expected OCP version templates were created
mapfile -t EXPECTED_VERSIONS < <(jq -r 'keys[] | gsub("\\."; "-")' drop-versions.json)
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

echo "Test passed: generate-catalog-template.sh created all expected catalog templates."

# Cleanup is handled by trap
