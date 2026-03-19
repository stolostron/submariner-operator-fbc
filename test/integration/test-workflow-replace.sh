#!/bin/bash
#
# test-workflow-replace.sh - Integration test for REPLACE scenario
#
# Scenario: A released version has critical bugs and must be skipped in the
# upgrade path. The next version (e.g., 0.21.3) replaces the broken one (0.21.2)
# by updating skipRange to jump over it.
#
# Why it matters: Prevents users from installing broken versions while preserving
# upgrade continuity. The broken version is removed from the catalog entirely.
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT_DIR=$(realpath "${SCRIPT_DIR}/../..")

source "${REPO_ROOT_DIR}/scripts/lib/test-helpers.sh"

cd "${REPO_ROOT_DIR}"

echo ""
echo "=== Integration Test: REPLACE Workflow ==="
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
        echo "submariner-0-21-def456	push"
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
            echo "quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:1112223334445556667778889990000aaabbbcccdddeeefff000111222333444" ;;
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
echo "$@" | grep -q "submariner-bundle-0-21" && exit 1
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
      # Remove old catalogs and create new ones
      rm -rf catalog-4-{14,15,16,17,18,19,20,21}
      mkdir -p catalog-4-{14,15,16,17,18,19,20,21}/{bundles,channels}
      for v in 14 15 16 17 18 19 20 21; do
        cat > "catalog-4-$v/bundles/bundle-v0.21.3.yaml" <<BUNDLE
schema: olm.bundle
name: submariner.v0.21.3
image: quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:1112223334445556667778889990000aaabbbcccdddeeefff000111222333444
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

echo "Running REPLACE workflow: 0.21.3 replaces 0.21.2..."
echo ""

if yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.21.2")' catalog-template.yaml | grep -q "submariner.v0.21.2"; then
  echo "✓ Old version 0.21.2 exists"
else
  echo "ERROR: Old version 0.21.2 doesn't exist!"
  exit 1
fi

if yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.21.3")' catalog-template.yaml | grep -q "submariner.v0.21.3"; then
  echo "ERROR: New version 0.21.3 already exists!"
  exit 1
fi

echo "✓ New version 0.21.3 doesn't exist yet"
echo ""

./scripts/update-bundle.sh --version 0.21.3 --snapshot submariner-0-21-def456 --replace 0.21.2 || true

#------------------------------------------------------------------------------
# Verify
#------------------------------------------------------------------------------

echo ""
echo "Verifying REPLACE workflow..."
echo ""

# REPLACE-specific checks: old bundle removed, new bundle swapped in with updated upgrade path
OLD_BUNDLE=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.21.2") | .name' catalog-template.yaml)
NEW_BUNDLE=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == "submariner.v0.21.3") | .name' catalog-template.yaml)

assert_equals "" "$OLD_BUNDLE" "Old bundle v0.21.2 removed from template"
assert_equals "submariner.v0.21.3" "$NEW_BUNDLE" "New bundle v0.21.3 added to template"

NEW_CHANNEL_ENTRY=$(yq eval '.entries[] | select(.schema == "olm.channel" and .name == "stable-0.21") | .entries[] | select(.name == "submariner.v0.21.3")' catalog-template.yaml)
SKIP_RANGE=$(echo "$NEW_CHANNEL_ENTRY" | yq eval '.skipRange' -)
REPLACES=$(echo "$NEW_CHANNEL_ENTRY" | yq eval '.replaces' -)

assert_equals ">=0.20.0 <0.21.3" "$SKIP_RANGE" "skipRange excludes v0.21.2"
assert_equals "submariner.v0.21.0" "$REPLACES" "Replaces field unchanged (inherits from v0.21.2)"

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
  echo "[SUCCESS] REPLACE workflow test passed"
  exit 0
else
  echo "FAILED: REPLACE workflow test"
  exit 1
fi
