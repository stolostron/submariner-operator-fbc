#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

echo "### Running all tests... ###"
echo ""

# Run unit tests first (fast feedback)
if [ -d "./test/unit" ]; then
  echo "=== Unit Tests ==="
  for test_script in ./test/unit/test-*.sh; do
    if [ -f "$test_script" ]; then
      echo ""
      echo "Running: $test_script"
      "$test_script"
    fi
  done
  echo ""
fi

# Run integration tests
echo "=== Integration Tests ==="
for test_script in ./test/integration/test-*.sh ./test/test-*.sh; do
  if [[ "$test_script" == "./test/test.sh" ]]; then
      continue
  fi
  echo ""
  echo "Running: $test_script"
  "$test_script"
done

echo ""
echo "### All tests complete ###"
