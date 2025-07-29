#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Ensure cleanup happens on exit
trap './scripts/cleanup-generated-files.sh' EXIT

echo "--> Cleaning up before test..."
./scripts/cleanup-generated-files.sh

echo "--> Running fetch-catalog-containerized.sh script..."
./build/archive/fetch-catalog-containerized.sh 4.19 submariner

echo "--> Verifying output..."

# Check that catalog-template.yaml was created
if [[ ! -f "catalog-template.yaml" ]]; then
  echo "Error: catalog-template.yaml was not generated."
  exit 1
fi
echo "  [SUCCESS] catalog-template.yaml was generated."
