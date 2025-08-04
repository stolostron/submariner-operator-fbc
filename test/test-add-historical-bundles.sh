#!/bin/bash
set -euo pipefail

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Read the historical bundle images from the YAML file
IMAGES=$(yq e '.historical_bundle_images[].image' "${REPO_ROOT_DIR}/test/historical-bundle-images.yaml")

for IMAGE in ${IMAGES}; do
  echo "--> Adding bundle: ${IMAGE}"
  make add-bundle BUNDLE_IMAGE="${IMAGE}"
  echo "--> Validating catalog after adding bundle: ${IMAGE}"
  make validate-catalog
done

echo "--> All historical bundles added."