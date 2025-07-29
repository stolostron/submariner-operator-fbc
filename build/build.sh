#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

echo "--> Generating catalog template..."
./scripts/generate-catalog-template.sh

echo "--> Rendering containerized catalog..."
./scripts/render-catalog-containerized.sh

echo "--> Build complete."
