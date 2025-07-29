#!/bin/bash

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Cleanup any previous runs
./build/cleanup-generated-files.sh

# Add a bundle
# Get bundle info
eval $(./scripts/get-bundle-metadata.sh DUMMY_BUNDLE_IMAGE)

# Add the bundle to the base catalog template
#./build/add-bundle-to-template.sh catalog-template.yaml "${BUNDLE_IMAGE}" "submariner-product.${BUNDLE_VERSION}-${BUNDLE_DIGEST:0:7}" "${BUNDLE_VERSION}" "${BUNDLE_CHANNELS}"
# TODO Add removal script

echo "### Running generate-catalog-template.sh ###"
./scripts/generate-catalog-template.sh

echo "### Running render-catalog-containerized.sh ###"
./build/render-catalog-containerized.sh

# Cleanup run
rm -f catalog-template-4-*.yaml

# Assert no difference in relevant files outside build/
echo "Checking for changes outside ignored directories..."
if ! git diff --exit-code -- . ':!build/' ':!scripts/' ':!test/' ':!.github/'; then
  echo "Error: Changes detected outside ignored directories. Please commit or discard them."
  exit 1
fi

# Assert no untracked or uncommitted changes outside build/
if git status --porcelain -- . ':!build/' ':!scripts/' ':!test/' ':!.github/' | grep -q .; then
  echo "Error: Untracked or uncommitted changes detected outside ignored directories. Please commit or discard them."
  exit 1
fi

echo "### Test complete ###"

for test_script in ./test/test-*.sh; do
  echo "### Running $test_script ###"
  "$test_script"
done

# Cleanup after run
./build/cleanup-generated-files.sh
