#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

# Initial cleanup
./scripts/reset-test-environment.sh

echo "### Running all tests... ###"

for test_script in ./test/test-*.sh; do
  if [[ "$test_script" == "./test/test.sh" ]]; then
      continue
  fi
  echo "### Running $test_script ###"
  "$test_script"
  ./scripts/reset-test-environment.sh
done

echo "### All tests complete ###"
