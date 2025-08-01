#!/bin/bash

set -e

./scripts/reset-test-environment.sh

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Test with DUMMY_BUNDLE_IMAGE
echo "Testing get-bundle-metadata.sh with DUMMY_BUNDLE_IMAGE..."
OUTPUT=$(./scripts/get-bundle-metadata.sh DUMMY_BUNDLE_IMAGE)

expected_digest="BUNDLE_DIGEST=sha256:d404c010f2134b00000000000000000000000000000000000000000000000000"
expected_version="BUNDLE_VERSION=v0.0.1"
expected_channels="BUNDLE_CHANNELS=alpha"

if [[ "${OUTPUT}" == *"${expected_digest}"* ]] && \
   [[ "${OUTPUT}" == *"${expected_version}"* ]] && \
   [[ "${OUTPUT}" == *"${expected_channels}"* ]]; then
  echo "Test passed: Correct metadata extracted for DUMMY_BUNDLE_IMAGE."
else
  echo "Test failed: Unexpected output for DUMMY_BUNDLE_IMAGE."
  echo "Expected:"
  echo "${expected_digest}"
  echo "${expected_version}"
  echo "${expected_channels}"
  echo "Got:"
  echo "${OUTPUT}"
  exit 1
fi

echo "All tests for get-bundle-metadata.sh passed."
