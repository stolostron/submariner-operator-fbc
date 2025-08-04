#!/bin/bash

set -euo pipefail

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Run the script
./scripts/generate-catalog-template.sh

# Basic verification: Check that the files were created
if [ ! -f catalog-template-4-14.yaml ]; then
  echo "Test failed: catalog-template-4-14.yaml was not created."
  exit 1
fi

if [ ! -f catalog-template-4-15.yaml ]; then
  echo "Test failed: catalog-template-4-15.yaml was not created."
  exit 1
fi

echo "Test passed: generate-catalog-template.sh ran without error and created the expected files."

# Cleanup
rm catalog-template-*-*.yaml
