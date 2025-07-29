#!/bin/bash

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Cleanup any previous runs
./build/cleanup-generated-files.sh

# Add a bundle
# FIXME This fails if added. Fix scripts to handle multiple bundles.
#./build/add-bundle.sh quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21:submariner-bundle-0-21-on-push-s22ll-build-container

echo "### Running generate-catalog-template.sh ###"
./build/generate-catalog-template.sh

echo "### Running render-catalog-containerized.sh ###"
./build/render-catalog-containerized.sh

# Cleanup run
rm -f catalog-template-4-*.yaml

# Assert no difference in relevant files outside build/
echo "Checking for changes outside 'build/' directory..."
if ! git diff --exit-code -- . ':!build/'; then
  echo "Error: Changes detected outside the 'build/' directory. Please commit or discard them."
  exit 1
fi

# Assert no untracked or uncommitted changes outside build/
if git status --porcelain -- . ':!build/' | grep -q .; then
  echo "Error: Untracked or uncommitted changes detected outside the 'build/' directory. Please commit or discard them."
  exit 1
fi

echo "### Test complete ###"

# Cleanup after run
./build/cleanup-generated-files.sh
