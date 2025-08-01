#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"



# Cleanup any previous runs
./scripts/cleanup-generated-files.sh

echo "### Running all tests... ###"

for test_script in ./test/test-*.sh; do
  if [[ "$test_script" == "./test/test.sh" ]]; then
      continue
  fi
  echo "### Running $test_script ###"
  "$test_script"
  ./scripts/check-generated-files-status.sh
done

echo "### All tests complete ###"

# Cleanup after run
./scripts/cleanup-generated-files.sh
