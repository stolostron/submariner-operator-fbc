#!/bin/bash

set -ex

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Cleanup any previous runs
rm -f catalog-template-4-*.yaml

# Remove committed catalogs
rm -rf catalog-4-*

#echo "### Running fetch-catalog.sh ###"
#./build/fetch-catalog.sh 4.19 submariner

echo "### Running generate-catalog-template.sh ###"
./build/generate-catalog-template.sh

echo "### Running render-catalog-containerized.sh ###"
./build/render-catalog-containerized.sh

# Cleanup run
rm -f catalog-template-4-*.yaml

# TODO Assert no difference in relevant files
git diff|cat
# TODO Assert no deleted things, or just smarter assert overall
git status

echo "### Test complete ###"
