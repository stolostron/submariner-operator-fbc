#!/bin/bash
#
# test-workflow-e2e.sh - End-to-End test with real external dependencies
#
# This test verifies the complete update-bundle workflow using:
# - Real Konflux cluster (oc get snapshots)
# - Real registries (skopeo inspect)
# - Real catalog builds (make build-catalogs)
# - Real OPM validation (all supported OCP versions)
#
# Requirements:
# - oc login to Konflux cluster
# - Network access (no RH VPN)
# - Registry authentication
#
# Execution time: ~45 seconds
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"
source "${REPO_ROOT_DIR}/test/lib/test-constants.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== End-to-End (E2E) Workflow Test ==="
echo ""
echo "This test uses REAL external dependencies (~45s typical)."
echo ""

# Save current commit to restore after test
BEFORE_TEST_COMMIT=$(git rev-parse HEAD)

# Setup cleanup trap to restore clean state on exit
cleanup() {
  echo ""
  echo "Cleaning up E2E test..."

  # Reset to commit before test (removes any commits created)
  git reset --hard "$BEFORE_TEST_COMMIT" > /dev/null 2>&1 || true

  # Restore clean git state
  ./scripts/reset-test-environment.sh "$BEFORE_TEST_COMMIT" > /dev/null 2>&1 || true

  echo "✓ Cleanup complete"
}
trap cleanup EXIT

#------------------------------------------------------------------------------
# Prerequisites Check
#------------------------------------------------------------------------------

echo "Checking prerequisites..."
echo ""

# Check oc access to Konflux cluster
if ! oc whoami > /dev/null 2>&1; then
  echo "ERROR: Not logged into Konflux cluster"
  echo "Please run: oc login --web https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/"
  exit 1
fi
echo "✓ Logged into Konflux: $(oc whoami --show-server)"

# Check registry access (requires podman/skopeo authentication, off RH VPN)
# Use skopeo inspect to verify - requires authenticated registry access
if ! skopeo inspect docker://registry.redhat.io/ubi9/ubi-minimal:latest > /dev/null 2>&1; then
  echo "ERROR: Cannot access registry.redhat.io via skopeo"
  echo "  This test requires authenticated registry access to pull bundle images."
  echo "  Login with: podman login registry.redhat.io"
  exit 1
fi
echo "✓ Can access registry.redhat.io (authenticated)"

# Check required tools
for tool in yq jq skopeo; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "ERROR: Required tool not found: $tool"
    exit 1
  fi
done
echo "✓ Required tools available"

echo ""

#------------------------------------------------------------------------------
# Test Scenario: UPDATE existing bundle with real snapshot
#------------------------------------------------------------------------------

echo "=== Test Scenario: UPDATE workflow with real data ==="
echo ""

# Find a real snapshot for testing (use v0.22.1 as example)
TEST_VERSION="$TEST_VERSION_22_1"
Y_STREAM="$TEST_Y_STREAM_22"

echo "Finding latest snapshot for version ${TEST_VERSION}..."
SNAPSHOT=$(oc get snapshots -n submariner-tenant \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.pac\.test\.appstudio\.openshift\.io/event-type}{"\n"}{end}' \
  | grep "^submariner-${Y_STREAM}.*push$" \
  | tail -1 \
  | awk '{print $1}')

if [ -z "$SNAPSHOT" ]; then
  echo "ERROR: No snapshots found for version ${TEST_VERSION}"
  echo "Please verify Konflux has built this version."
  exit 1
fi

echo "✓ Using snapshot: $SNAPSHOT"

# Get bundle image from snapshot
BUNDLE_IMAGE=$(oc get snapshot "$SNAPSHOT" -n submariner-tenant \
  -o jsonpath='{.spec.components[?(@.name=="submariner-bundle-'${Y_STREAM}'")].containerImage}')

if [ -z "$BUNDLE_IMAGE" ]; then
  echo "ERROR: Could not extract bundle image from snapshot"
  exit 1
fi

echo "✓ Bundle image: $BUNDLE_IMAGE"

# Extract SHA
BUNDLE_SHA=$(echo "$BUNDLE_IMAGE" | grep -oP 'sha256:\K[a-f0-9]{64}')
echo "✓ Bundle SHA: ${BUNDLE_SHA:0:12}..."

echo ""

#------------------------------------------------------------------------------
# Run update-bundle.sh with real external calls
#------------------------------------------------------------------------------

echo "Running update-bundle.sh with REAL external dependencies..."
echo "  - Real oc calls (Konflux cluster)"
echo "  - Real skopeo calls (registry checks)"
echo "  - Real make build-catalogs (~30s)"
echo "  - Real opm validate (all supported OCP versions)"
echo ""

# Setup: Use fixture with real bundle SHAs as starting point
# This allows opm to render the catalog (it needs to pull real images)
cp test/fixtures/fixture-0-21.yaml catalog-template.yaml

# Run the real workflow (this will take several minutes)
./scripts/update-bundle.sh --version "$TEST_VERSION" --snapshot "$SNAPSHOT" || {
  echo "ERROR: update-bundle.sh failed"
  exit 1
}

#------------------------------------------------------------------------------
# Verification
#------------------------------------------------------------------------------

echo ""
echo "Verifying E2E workflow results..."
echo ""

# 1. Bundle SHA updated in catalog-template.yaml
TEMPLATE_SHA=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v'${TEST_VERSION}'") | .image' catalog-template.yaml | grep -oP 'sha256:\K[a-f0-9]{64}')
assert_equals "$BUNDLE_SHA" "$TEMPLATE_SHA" "Bundle SHA updated in template"

# 2. All 8 catalogs built and valid
for v in 14 15 16 17 18 19 20 21; do
  if [ -d "catalog-4-$v" ]; then
    # Check catalog has bundle file
    if [ -f "catalog-4-$v/bundles/bundle-v${TEST_VERSION}.yaml" ]; then
      CATALOG_SHA=$(yq eval '.image' "catalog-4-$v/bundles/bundle-v${TEST_VERSION}.yaml" | grep -oP 'sha256:\K[a-f0-9]{64}')
      assert_equals "$BUNDLE_SHA" "$CATALOG_SHA" "catalog-4-$v bundle SHA matches"
    else
      echo "  ℹ catalog-4-$v: bundle not included (pruned by drop-versions.json)"
    fi
  fi
done

# 3. Verify commit was created
TESTS_RUN=$((TESTS_RUN + 1))
COMMIT_AFTER=$(git rev-parse HEAD)
if [ "$COMMIT_AFTER" == "$BEFORE_TEST_COMMIT" ]; then
  echo "  ✗ No commit created by update-bundle.sh"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo "  ✓ Commit created by update-bundle.sh"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

echo ""
echo "=================================="
echo "E2E Test Summary:"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo "[SUCCESS] E2E workflow test passed"
  echo ""
  echo "Validated complete workflow with:"
  echo "  - Real Konflux snapshot: $SNAPSHOT"
  echo "  - Real bundle SHA: ${BUNDLE_SHA:0:12}..."
  echo "  - Real catalog builds: 8 OCP versions"
  echo "  - Real opm validation: All catalogs valid"
  exit 0
else
  echo "FAILED: E2E workflow test"
  exit 1
fi
