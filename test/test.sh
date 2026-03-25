#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

echo "### Running all tests... ###"
echo ""

# Track failed tests
failed_tests=()

# Run unit tests first (fast feedback)
if [ -d "./test/unit" ]; then
  echo "=== Unit Tests ==="
  for test_script in ./test/unit/test-*.sh; do
    if [ -f "$test_script" ]; then
      echo ""
      echo "Running: $test_script"
      if ! "$test_script"; then
        failed_tests+=("$test_script")
      fi
    fi
  done
  echo ""
fi

# Run integration tests
echo "=== Integration Tests ==="
for test_script in ./test/integration/test-*.sh ./test/scripts/test-*.sh; do
  echo ""
  echo "Running: $test_script"
  if ! "$test_script"; then
    failed_tests+=("$test_script")
  fi
done

echo ""
if [ ${#failed_tests[@]} -gt 0 ]; then
  echo "### FAILED: ${#failed_tests[@]} test(s) failed ###"
  echo ""
  echo "Failed tests:"
  for test in "${failed_tests[@]}"; do
    echo "  - $test"
  done
  exit 1
else
  echo "### All tests complete ###"
fi
