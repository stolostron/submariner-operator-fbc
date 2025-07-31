#!/bin/bash

set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/..")

# Run from the repo root
cd "${REPO_ROOT_DIR}"

check_git_status() {
  echo "--> Verifying git status..."
  # Assert no difference in relevant files outside of some dirs
  if ! git diff --exit-code -- . ':!build/' ':!scripts/' ':!test/' ':!.github/'; then
    echo "Error: Changes detected outside ignored directories after running the previous test."
    exit 1
  fi

  # Assert no untracked or uncommitted changes outside of some dirs
  if git status --porcelain -- . ':!build/' ':!scripts/' ':!test/' ':!.github/' | grep -q .; then
    echo "Error: Untracked or uncommitted changes detected outside ignored directories after running the previous test."
    exit 1
  fi
  echo "  [SUCCESS] Git status is clean."
}

# Cleanup any previous runs
./scripts/cleanup-generated-files.sh

echo "### Running all tests... ###"

for test_script in ./test/test-*.sh; do
  if [[ "$test_script" == "./test/test.sh" ]]; then
      continue
  fi
  echo "### Running $test_script ###"
  "$test_script"
  check_git_status
done

echo "### All tests complete ###"

# Cleanup after run
./scripts/cleanup-generated-files.sh
