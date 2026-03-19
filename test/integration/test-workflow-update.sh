#!/bin/bash
#
# test-workflow-update.sh - Integration test for UPDATE scenario
#
# Scenario: Konflux rebuilds an existing bundle version with a new image SHA.
# This happens when the bundle manifest or operator code changes but the
# Submariner version stays the same (e.g., 0.21.2 rebuilt with security patch).
#
# Why it matters: The FBC must track the latest bundle SHA to ensure operators
# install the most recent build. This is the most common scenario (~40% of updates).
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== Integration Test: UPDATE Workflow ==="
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
        echo "submariner-0-21-abc123	push"
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
            echo "quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:abc123def4567890abc123def4567890abc123def4567890abc123def4567890" ;;
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
        cat > "catalog-4-$v/bundles/bundle-v0.21.2.yaml" <<BUNDLE
schema: olm.bundle
name: submariner.v0.21.2
image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:abc123def4567890abc123def4567890abc123def4567890abc123def4567890
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

echo "Running UPDATE workflow for version 0.21.2..."
echo ""

# Capture BEFORE state (must be done BEFORE update runs)
ORIGINAL_SHA=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.21.2") | .image' catalog-template.yaml | grep -oP 'sha256:\K[a-f0-9]{64}')
CHANNEL_BEFORE=$(yq eval '.entries[] | select(.schema == "olm.channel" and .name == "stable-0.21") | .entries[] | select(.name == "submariner.v0.21.2")' catalog-template.yaml)
REPLACES_BEFORE=$(echo "$CHANNEL_BEFORE" | yq eval '.replaces' -)
SKIP_RANGE_BEFORE=$(echo "$CHANNEL_BEFORE" | yq eval '.skipRange' -)

echo "Original SHA: ${ORIGINAL_SHA:0:12}..."
echo "New SHA:      abc123def456..."
echo ""

./scripts/update-bundle.sh --version 0.21.2 --snapshot submariner-0-21-abc123 || true

#------------------------------------------------------------------------------
# Verify
#------------------------------------------------------------------------------

echo ""
echo "Verifying UPDATE workflow..."
echo ""

# 1. Bundle SHA updated (core UPDATE behavior)
NEW_SHA=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.21.2") | .image' catalog-template.yaml | grep -oP 'sha256:\K[a-f0-9]{64}')
assert_equals "abc123def4567890abc123def4567890abc123def4567890abc123def4567890" "$NEW_SHA" "Bundle SHA updated in template"

# 2. Channel entry unchanged (distinguishes UPDATE from REPLACE)
CHANNEL_AFTER=$(yq eval '.entries[] | select(.schema == "olm.channel" and .name == "stable-0.21") | .entries[] | select(.name == "submariner.v0.21.2")' catalog-template.yaml)
REPLACES_AFTER=$(echo "$CHANNEL_AFTER" | yq eval '.replaces' -)
SKIP_RANGE_AFTER=$(echo "$CHANNEL_AFTER" | yq eval '.skipRange' -)

assert_equals "$REPLACES_BEFORE" "$REPLACES_AFTER" "Channel replaces field unchanged"
assert_equals "$SKIP_RANGE_BEFORE" "$SKIP_RANGE_AFTER" "Channel skipRange unchanged"

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
  echo "[SUCCESS] UPDATE workflow test passed"
  exit 0
else
  echo "FAILED: UPDATE workflow test"
  exit 1
fi
