#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

echo "### Running all tests... ###"

for test_script in ./test/test-*.sh; do
  if [[ "$test_script" == "./test/test.sh" ]]; then
      continue
  fi
  echo "### Running $test_script ###"
  "$test_script"
done

echo "### All tests complete ###"

./scripts/reset-test-environment.sh
