#!/bin/bash
#
# test-workflow-add.sh - Integration test for ADD scenario
#
# Scenario: First release of a new Submariner minor version (e.g., 0.24.0).
# Creates a new upgrade channel and bundle entry from scratch.
#
# Why it matters: New Y-stream releases require creating new channels with proper
# skipRange and upgrade paths. Without this, users cannot upgrade to new versions.
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== Integration Test: ADD Workflow ==="
echo ""

# Save current commit to restore after test (update-bundle.sh creates commits)
BEFORE_TEST_COMMIT=$(git rev-parse HEAD)

# Setup: Copy fixture to catalog-template.yaml
cp test/fixtures/fixture-0-21.yaml catalog-template.yaml

#------------------------------------------------------------------------------
# Mocks
#------------------------------------------------------------------------------

oc() {
  case "$1" in
    get)
      if [[ "$2" == "snapshots" ]]; then
        echo "submariner-0-24-xyz789	push"
      elif [[ "$2" == "snapshot" ]]; then
        shift 2
        local output_format=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -o) output_format="$2"; shift 2 ;;
            -n) shift 2 ;;
            *) shift ;;
          esac
        done
        case "$output_format" in
          *test*appstudio*)
            echo '[{"scenario":"submariner-fbc-4-20-operator","status":"TestPassed"}]' ;;
          jsonpath=*)
            echo "quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-24@sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210" ;;
          *)
            return 0 ;;
        esac
      fi
      ;;
  esac
}
export -f oc

MOCK_BIN_DIR="/tmp/submariner-fbc-test-bin-$$"
mkdir -p "$MOCK_BIN_DIR"

cat > "$MOCK_BIN_DIR/skopeo" <<'EOF'
#!/bin/bash
echo "$@" | grep -q "submariner-bundle-0-24" && exit 1
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/skopeo"

cat > "$MOCK_BIN_DIR/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF
chmod +x "$MOCK_BIN_DIR/timeout"

export PATH="$MOCK_BIN_DIR:$PATH"

make() {
  case "$1" in
    build-catalogs)
      mkdir -p catalog-4-{14,15,16,17,18,19,20,21}/{bundles,channels}
      for v in 14 15 16 17 18 19 20 21; do
        cat > "catalog-4-$v/bundles/bundle-v0.24.0.yaml" <<BUNDLE
schema: olm.bundle
name: submariner.v0.24.0
image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-24@sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
BUNDLE
      done
      ;;
    validate-catalogs) ;;
    opm)
      mkdir -p bin
      echo -e '#!/bin/bash\nexit 0' > bin/opm
      chmod +x bin/opm
      ;;
    *) command make "$@" ;;
  esac
}
export -f make

#------------------------------------------------------------------------------
# Test
#------------------------------------------------------------------------------

echo "Running ADD workflow for new version 0.24.0..."
echo ""

if yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.24.0")' catalog-template.yaml | grep -q "submariner.v0.24.0"; then
  echo "ERROR: Version 0.24.0 already exists in catalog!"
  exit 1
fi

echo "✓ Confirmed 0.24.0 doesn't exist yet"
echo ""

./scripts/update-bundle.sh --version 0.24.0 --snapshot submariner-0-24-xyz789 || true

#------------------------------------------------------------------------------
# Verify
#------------------------------------------------------------------------------

echo ""
echo "Verifying ADD workflow..."
echo ""

# ADD-specific checks: new bundle + channel creation + first entry without replaces
# 1. Bundle entry added to catalog entries array
BUNDLE_EXISTS=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.24.0") | .name' catalog-template.yaml)
assert_equals "submariner.v0.24.0" "$BUNDLE_EXISTS" "Bundle entry added to catalog"

# 2. Bundle image SHA correct
BUNDLE_IMAGE=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.24.0") | .image' catalog-template.yaml)
assert_equals "quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-24@sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210" "$BUNDLE_IMAGE" "Bundle image SHA correct"

# 3. New channel created
CHANNEL_EXISTS=$(yq eval '.entries[] | select(.schema == "olm.channel" and .name == "stable-0.24") | .name' catalog-template.yaml)
assert_equals "stable-0.24" "$CHANNEL_EXISTS" "New channel stable-0.24 created"

# 4. Bundle added as first entry in channel
CHANNEL_ENTRY=$(yq eval '.entries[] | select(.schema == "olm.channel" and .name == "stable-0.24") | .entries[0]' catalog-template.yaml)
ENTRY_NAME=$(echo "$CHANNEL_ENTRY" | yq eval '.name' -)
assert_equals "submariner.v0.24.0" "$ENTRY_NAME" "Bundle added as first entry in channel"

# 5. First entry has no replaces field
REPLACES=$(echo "$CHANNEL_ENTRY" | yq eval '.replaces' -)
assert_equals "null" "$REPLACES" "First entry has no replaces field"

# 6. First entry has correct skipRange (>=0.18.0 <0.24.0)
SKIP_RANGE=$(echo "$CHANNEL_ENTRY" | yq eval '.skipRange' -)
assert_equals ">=0.18.0 <0.24.0" "$SKIP_RANGE" "First entry skipRange correct"

# 7. defaultChannel updated to new channel
DEFAULT_CHANNEL=$(yq eval '.entries[] | select(.schema == "olm.package") | .defaultChannel' catalog-template.yaml)
assert_equals "stable-0.24" "$DEFAULT_CHANNEL" "defaultChannel updated to stable-0.24"

#------------------------------------------------------------------------------
# Cleanup
#------------------------------------------------------------------------------

# Reset to commit before test (removes any commits created by update-bundle.sh)
git reset --hard "$BEFORE_TEST_COMMIT" > /dev/null 2>&1

[ -n "${MOCK_BIN_DIR:-}" ] && rm -rf "$MOCK_BIN_DIR"
./scripts/reset-test-environment.sh "$BEFORE_TEST_COMMIT" > /dev/null 2>&1

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

echo ""
echo "=================================="
echo "Test Summary:"
echo "  Total:  $TESTS_RUN"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo "[SUCCESS] ADD workflow test passed"
  exit 0
else
  echo "FAILED: ADD workflow test"
  exit 1
fi
