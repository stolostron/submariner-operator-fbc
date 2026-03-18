#!/bin/bash
#
# update-bundle.sh - Automate FBC catalog updates for Submariner releases
#
# Usage: ./scripts/update-bundle.sh --version X.Y.Z [--snapshot name] [--replace X.Y.Z] [--auto-convert]
#
# Scenarios:
#   UPDATE: Rebuild with new SHA (most common)
#   ADD: New Y-stream version
#   REPLACE: Skip problematic version
#

set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$(realpath "${SCRIPT_DIR}/..")

# Global variables
VERSION=""
SNAPSHOT=""
REPLACE=""
AUTO_CONVERT=false
BUNDLE_IMAGE=""
BUNDLE_SHA=""
SCENARIO=""
YSTREAM=""
YSTREAM_DASH=""

# Constants
SKIPRANGE_BASE="0.18.0"  # Minimum version for skipRange (Submariner 0.18+)

#------------------------------------------------------------------------------
# parse_args - Parse command-line arguments
#------------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --version) VERSION="$2"; shift 2 ;;
      --snapshot) SNAPSHOT="$2"; shift 2 ;;
      --replace) REPLACE="$2"; shift 2 ;;
      --auto-convert) AUTO_CONVERT=true; shift ;;
      *) echo "ERROR: Unknown argument: $1"; exit 1 ;;
    esac
  done

  # Validation
  if [ -z "$VERSION" ]; then
    echo "ERROR: --version required"
    echo ""
    echo "Usage: $0 --version X.Y.Z [--snapshot name] [--replace X.Y.Z] [--auto-convert]"
    exit 1
  fi

  # Normalize version (strip leading v if present)
  VERSION="${VERSION#v}"
  REPLACE="${REPLACE#v}"

  # Validate version format (X.Y.Z) to prevent cryptic yq errors
  if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Invalid version format '$VERSION' (expected X.Y.Z, e.g., 0.22.1)"
    exit 1
  fi

  # Extract Y-stream (0.22.1 → 0.22)
  YSTREAM="${VERSION%.*}"
  YSTREAM_DASH="${YSTREAM//./-}"
}

#------------------------------------------------------------------------------
# find_snapshot - Find/validate snapshot and extract bundle image
#------------------------------------------------------------------------------
find_snapshot() {
  echo "=== Finding Snapshot ==="

  if [ -z "$SNAPSHOT" ]; then
    echo "Finding latest passing snapshot for version $YSTREAM_DASH..."

    SNAPSHOT=$(oc get snapshots -n submariner-tenant --sort-by=.metadata.creationTimestamp \
      | grep "^submariner-$YSTREAM_DASH" \
      | tail -1 \
      | awk '{print $1}')

    if [ -z "$SNAPSHOT" ]; then
      echo "ERROR: No snapshot found for version $YSTREAM_DASH"
      echo ""
      echo "Available snapshots:"
      oc get snapshots -n submariner-tenant --sort-by=.metadata.creationTimestamp | grep "^submariner-" | tail -5
      exit 1
    fi
    echo "✓ Using snapshot: $SNAPSHOT"
  else
    echo "Using explicit snapshot: $SNAPSHOT"
  fi

  # Verify snapshot exists
  if ! oc get snapshot "$SNAPSHOT" -n submariner-tenant >/dev/null 2>&1; then
    echo "ERROR: Snapshot $SNAPSHOT not found"
    exit 1
  fi

  # Extract bundle image from snapshot
  BUNDLE_COMPONENT="submariner-bundle-${YSTREAM_DASH}"
  BUNDLE_IMAGE=$(oc get snapshot "$SNAPSHOT" -n submariner-tenant \
    -o jsonpath="{.spec.components[?(@.name=='$BUNDLE_COMPONENT')].containerImage}")

  if [ -z "$BUNDLE_IMAGE" ]; then
    echo "ERROR: Bundle component $BUNDLE_COMPONENT not found in snapshot"
    echo ""
    echo "Available components:"
    oc get snapshot "$SNAPSHOT" -n submariner-tenant -o jsonpath='{.spec.components[*].name}' | tr ' ' '\n'
    exit 1
  fi

  echo "✓ Bundle image: $BUNDLE_IMAGE"

  # Extract SHA
  BUNDLE_SHA=$(echo "$BUNDLE_IMAGE" | grep -oP 'sha256:\K[a-f0-9]+')
  if [ -z "$BUNDLE_SHA" ]; then
    echo "ERROR: Could not extract SHA from bundle image"
    exit 1
  fi
  echo "✓ Bundle SHA: ${BUNDLE_SHA:0:12}..."
  echo ""
}

#------------------------------------------------------------------------------
# detect_scenario - Determine ADD/UPDATE/REPLACE based on catalog state
#------------------------------------------------------------------------------
detect_scenario() {
  echo "=== Detecting Scenario ==="

  cd "$REPO_ROOT"

  # Check if bundle entry exists
  BUNDLE_NAME="submariner.v${VERSION}"
  BUNDLE_EXISTS=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "'"$BUNDLE_NAME"'")' catalog-template.yaml)

  # Check if version exists in any channel
  CHANNEL_EXISTS=$(yq '.entries[] | select(.schema == "olm.channel") | .entries[] | select(.name == "'"$BUNDLE_NAME"'")' catalog-template.yaml)

  # Scenario detection logic
  if [ -n "$REPLACE" ]; then
    # User explicitly requested REPLACE scenario
    OLD_BUNDLE_NAME="submariner.v${REPLACE}"
    OLD_BUNDLE_EXISTS=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "'"$OLD_BUNDLE_NAME"'")' catalog-template.yaml)

    if [ -z "$OLD_BUNDLE_EXISTS" ]; then
      echo "ERROR: Cannot replace - version $REPLACE not found in catalog"
      exit 1
    fi

    if [ -n "$BUNDLE_EXISTS" ]; then
      echo "ERROR: Cannot replace - version $VERSION already exists in catalog"
      exit 1
    fi

    SCENARIO="REPLACE"
    echo "✓ Scenario: REPLACE (v$REPLACE → v$VERSION)"

  elif [ -z "$BUNDLE_EXISTS" ] && [ -z "$CHANNEL_EXISTS" ]; then
    # Version doesn't exist anywhere - ADD scenario
    SCENARIO="ADD"
    echo "✓ Scenario: ADD (new version)"

  elif [ -n "$BUNDLE_EXISTS" ] && [ -n "$CHANNEL_EXISTS" ]; then
    # Version exists in both - UPDATE scenario (SHA change)
    SCENARIO="UPDATE"
    echo "✓ Scenario: UPDATE (rebuild)"

  else
    # Inconsistent state
    echo "ERROR: Inconsistent catalog state for version $VERSION"
    echo "  Bundle exists: $([ -n "$BUNDLE_EXISTS" ] && echo yes || echo no)"
    echo "  Channel exists: $([ -n "$CHANNEL_EXISTS" ] && echo yes || echo no)"
    exit 1
  fi

  echo ""
}

#------------------------------------------------------------------------------
# audit_bundle_urls - Check for quay.io bundles that should be converted
#------------------------------------------------------------------------------
audit_bundle_urls() {
  echo "=== Auditing Bundle URLs ==="
  
  cd "$REPO_ROOT"

  local NEEDS_CONVERSION=false
  UNRELEASED_BUNDLES=()  # Global array for use by convert function
  CONVERTIBLE_BUNDLES=()  # Global array for use by convert function
  
  # Find all quay.io bundles
  local QUAY_BUNDLES=$(yq '.entries[] | select(.schema == "olm.bundle" and (.image | contains("quay.io"))) | {"name": .name, "image": .image}' catalog-template.yaml -o json | jq -c '.')

  if [ -z "$QUAY_BUNDLES" ]; then
    echo "✓ No quay.io bundles found (all use registry.redhat.io)"
    echo ""
    return 0
  fi


  local bundle_count=0
  local convertible_count=0
  local unreleased_count=0


  while IFS= read -r bundle; do

    local name=$(echo "$bundle" | jq -r '.name')
    local image=$(echo "$bundle" | jq -r '.image')
    local sha=$(echo "$image" | grep -oP 'sha256:\K[a-f0-9]+')

    ((bundle_count++)) || true


    # Check if bundle exists at registry.redhat.io
    local prod_image="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:$sha"

    # Temporarily disable exit-on-error to check image existence
    set +e
    timeout 10 skopeo inspect "docker://$prod_image" >/dev/null 2>&1
    local exists=$?
    set -e

    if [ $exists -eq 0 ]; then
      echo "⚠️  $name: RELEASED but using quay.io URL"
      echo "   Current:  $image"
      echo "   Available: $prod_image"
      CONVERTIBLE_BUNDLES+=("$name")
      NEEDS_CONVERSION=true
      ((convertible_count++)) || true
    else
      echo "ℹ️  $name: UNRELEASED (quay.io workspace URL)"
      UNRELEASED_BUNDLES+=("$name")
      ((unreleased_count++)) || true
    fi
  done <<< "$QUAY_BUNDLES"
  
  echo ""
  echo "Summary: $bundle_count quay.io bundle(s) - $convertible_count convertible, $unreleased_count unreleased"
  
  if [ "$NEEDS_CONVERSION" = true ]; then
    if [ "$AUTO_CONVERT" = true ]; then
      echo "🔄 Auto-convert enabled - will convert released bundles"
    else
      echo "💡 Tip: Use --auto-convert to automatically convert released bundles"
    fi
  fi
  
  echo ""

  # Arrays are global and accessible by convert_released_bundles()

  return 0
}

#------------------------------------------------------------------------------
# convert_released_bundles - Convert quay.io bundles to registry.redhat.io
#------------------------------------------------------------------------------
convert_released_bundles() {
  if [ ${#CONVERTIBLE_BUNDLES[@]} -eq 0 ]; then
    return 0
  fi
  
  echo "=== Converting Released Bundles ===" 
  
  cd "$REPO_ROOT"
  
  for name in "${CONVERTIBLE_BUNDLES[@]}"; do
    # Get current image
    local current_image=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "'"$name"'") | .image' catalog-template.yaml)
    local sha=$(echo "$current_image" | grep -oP 'sha256:\K[a-f0-9]+')
    local new_image="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:$sha"
    
    # Update template
    yq '(.entries[] | select(.schema == "olm.bundle" and .name == "'"$name"'") | .image) = "'"$new_image"'"' catalog-template.yaml -i
    
    echo "✓ $name: quay.io → registry.redhat.io"
  done
  
  echo "✓ Converted ${#CONVERTIBLE_BUNDLES[@]} bundle(s)"
  echo ""
}


#------------------------------------------------------------------------------
# update_template_add - ADD scenario: new channel + bundle
#------------------------------------------------------------------------------
update_template_add() {
  echo "=== Adding New Bundle ==="

  cd "$REPO_ROOT"

  BUNDLE_NAME="submariner.v${VERSION}"
  CHANNEL="stable-${YSTREAM}"

  # Add bundle entry to catalog-template.yaml
  echo "Adding bundle entry..."
  BUNDLE_ENTRY="
  name: $BUNDLE_NAME
  image: $BUNDLE_IMAGE
  schema: olm.bundle
" yq '.entries += env(BUNDLE_ENTRY)' -i catalog-template.yaml

  echo "✓ Added bundle entry: $BUNDLE_NAME"

  # Check if channel exists
  CHANNEL_EXISTS=$(yq '.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'")' catalog-template.yaml)

  if [ -z "$CHANNEL_EXISTS" ]; then
    # Create new channel
    echo "Creating new channel: $CHANNEL"
    NEW_CHANNEL="
  name: $CHANNEL
  package: submariner
  schema: olm.channel
  entries: []
" yq '.entries += env(NEW_CHANNEL)' -i catalog-template.yaml

    # Update defaultChannel to new Y-stream
    echo "Updating defaultChannel to $CHANNEL..."
    yq '.entries[] |= select(.schema == "olm.package").defaultChannel = "'"$CHANNEL"'"' -i catalog-template.yaml
    echo "✓ Created channel and updated defaultChannel"

    # Update .tekton/images-mirror-set.yaml with new Y-stream version
    echo "Updating image mirror set for new Y-stream..."
    if [ -f .tekton/images-mirror-set.yaml ]; then
      # Extract previous Y-stream from existing mirror entries
      # Look for pattern like "lighthouse-agent-0-22" to extract "0-22"
      PREV_YSTREAM_DASH=$(grep -oP 'lighthouse-agent-\K[0-9]+-[0-9]+' .tekton/images-mirror-set.yaml | head -1)

      if [ -n "$PREV_YSTREAM_DASH" ]; then
        # Check for unreleased bundles from previous Y-stream before updating mirrors
        local OLD_YSTREAM_BUNDLES=$(yq '.entries[] | select(.schema == "olm.bundle" and (.image | contains("'"submariner-bundle-${PREV_YSTREAM_DASH}"'")))' catalog-template.yaml)

        if [ -n "$OLD_YSTREAM_BUNDLES" ]; then
          echo ""
          echo "⚠️  WARNING: Found unreleased bundles using -${PREV_YSTREAM_DASH} mirrors:"
          echo "$OLD_YSTREAM_BUNDLES" | yq '.name' | sed 's/^/   - /'
          echo ""
          echo "   These bundles will lose mirror access after updating to -${YSTREAM_DASH}"
          echo "   Options:"
          echo "     1. Remove unreleased bundles from catalog (recommended if never releasing)"
          echo "     2. Convert to registry.redhat.io if released (use --auto-convert)"
          echo "     3. Keep both mirror versions (will accumulate old versions)"
          echo ""

          # Give user a chance to abort
          if [ -t 0 ]; then
            read -p "   Continue anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
              echo "Aborted by user"
              exit 1
            fi
          else
            echo "   Non-interactive mode: proceeding automatically"
          fi
          echo ""
        fi

        # Replace all component version suffixes
        sed -i "s/-${PREV_YSTREAM_DASH}/-${YSTREAM_DASH}/g" .tekton/images-mirror-set.yaml
        echo "✓ Updated image mirror set: -$PREV_YSTREAM_DASH → -$YSTREAM_DASH"
      else
        echo "⚠️  WARNING: Could not detect previous Y-stream version in .tekton/images-mirror-set.yaml"
        echo "   Manually update component version suffixes to -$YSTREAM_DASH"
      fi
    else
      echo "⚠️  WARNING: .tekton/images-mirror-set.yaml not found"
    fi
  else
    echo "Channel $CHANNEL already exists"
  fi

  # Determine channel entry details
  ENTRIES_IN_CHANNEL=$(yq '.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries | length' catalog-template.yaml)

  if [ "$ENTRIES_IN_CHANNEL" = "0" ]; then
    # First entry in channel (no replaces)
    echo "Adding as first entry in channel (no replaces)..."
    CHANNEL_ENTRY="
  name: $BUNDLE_NAME
  skipRange: '>=${SKIPRANGE_BASE} <${VERSION#v}'
" yq '.entries[] |= select(.schema == "olm.channel") |= select(.name == "'"$CHANNEL"'").entries += env(CHANNEL_ENTRY)' -i catalog-template.yaml
    echo "✓ Added first entry to channel $CHANNEL"
  else
    # Subsequent entry (with replaces)
    REPLACES_BUNDLE_NAME=$(yq '.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries[-1].name' catalog-template.yaml)
    REPLACES_VERSION="${REPLACES_BUNDLE_NAME#submariner.v}"

    echo "Adding with replaces: $REPLACES_BUNDLE_NAME"
    SKIP_RANGE_VAL=">=${REPLACES_VERSION} <${VERSION#v}"
    CHANNEL_ENTRY="
  name: $BUNDLE_NAME
  replaces: $REPLACES_BUNDLE_NAME
  skipRange: '$SKIP_RANGE_VAL'
" yq '.entries[] |= select(.schema == "olm.channel") |= select(.name == "'"$CHANNEL"'").entries += env(CHANNEL_ENTRY)' -i catalog-template.yaml
    echo "✓ Added entry to channel $CHANNEL (skipRange: $SKIP_RANGE_VAL)"
  fi

  echo ""
}

#------------------------------------------------------------------------------
# update_template_update - UPDATE scenario: SHA replacement
#------------------------------------------------------------------------------
update_template_update() {
  echo "=== Updating Bundle SHA ==="

  cd "$REPO_ROOT"

  BUNDLE_NAME="submariner.v${VERSION}"

  # Get current image to show diff
  CURRENT_IMAGE=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "'"$BUNDLE_NAME"'").image' catalog-template.yaml)
  CURRENT_SHA=$(echo "$CURRENT_IMAGE" | grep -oP 'sha256:\K[a-f0-9]+' || echo "unknown")

  echo "Current SHA: ${CURRENT_SHA:0:12}..."
  echo "New SHA:     ${BUNDLE_SHA:0:12}..."

  if [ "$CURRENT_SHA" = "$BUNDLE_SHA" ]; then
    echo "⚠️  WARNING: SHA unchanged - bundle already at this version"
    echo "Proceeding anyway to rebuild catalogs..."
  fi

  # Update image SHA in catalog-template.yaml
  echo "Updating bundle image..."
  yq '.entries[] |= select(.schema == "olm.bundle" and .name == "'"$BUNDLE_NAME"'").image = "'"$BUNDLE_IMAGE"'"' -i catalog-template.yaml

  echo "✓ Updated $BUNDLE_NAME SHA in catalog-template.yaml"
  echo ""
}

#------------------------------------------------------------------------------
# update_template_replace - REPLACE scenario: rename entries
#------------------------------------------------------------------------------
update_template_replace() {
  echo "=== Replacing Bundle Version ==="

  cd "$REPO_ROOT"

  OLD_BUNDLE_NAME="submariner.v${REPLACE}"
  NEW_BUNDLE_NAME="submariner.v${VERSION}"
  CHANNEL="stable-${YSTREAM}"

  echo "Replacing: $OLD_BUNDLE_NAME → $NEW_BUNDLE_NAME"

  # Get old bundle image to show diff
  OLD_IMAGE=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "'"$OLD_BUNDLE_NAME"'").image' catalog-template.yaml)
  OLD_SHA=$(echo "$OLD_IMAGE" | grep -oP 'sha256:\K[a-f0-9]+' || echo "unknown")

  echo "Old SHA: ${OLD_SHA:0:12}..."
  echo "New SHA: ${BUNDLE_SHA:0:12}..."

  # Update bundle entry - rename and update image
  echo "Updating bundle entry..."

  # First update the name
  yq '.entries[] |= (select(.schema == "olm.bundle" and .name == "'"$OLD_BUNDLE_NAME"'") | .name = "'"$NEW_BUNDLE_NAME"'")' -i catalog-template.yaml

  # Then update the image
  yq '.entries[] |= (select(.schema == "olm.bundle" and .name == "'"$NEW_BUNDLE_NAME"'") | .image = "'"$BUNDLE_IMAGE"'")' -i catalog-template.yaml

  echo "✓ Updated bundle entry"

  # Update channel entry - rename and update skipRange
  echo "Updating channel entry..."

  # Verify channel entry exists for old version
  OLD_CHANNEL_ENTRY=$(yq '.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries[] | select(.name == "'"$OLD_BUNDLE_NAME"'")' catalog-template.yaml)
  if [ -z "$OLD_CHANNEL_ENTRY" ]; then
    echo "ERROR: Channel entry for $OLD_BUNDLE_NAME not found in $CHANNEL"
    exit 1
  fi

  # Get the replaces value to preserve it
  REPLACES_VALUE=$(yq '.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries[] | select(.name == "'"$OLD_BUNDLE_NAME"'").replaces // ""' catalog-template.yaml)

  # Update skipRange pattern (e.g., <0.21.1 → <0.21.2)
  NEW_VERSION_NUM="${VERSION#v}"

  if [ -n "$REPLACES_VALUE" ]; then
    # Has replaces - extract base version from skipRange
    SKIP_BASE=$(yq '.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries[] | select(.name == "'"$OLD_BUNDLE_NAME"'").skipRange' catalog-template.yaml | grep -oP '>=\K[0-9.]+' || echo "")

    if [ -n "$SKIP_BASE" ]; then
      NEW_SKIP_RANGE=">=${SKIP_BASE} <${NEW_VERSION_NUM}"
    else
      # Fallback if can't parse - use replaces version
      REPLACES_VERSION="${REPLACES_VALUE#submariner.v}"
      NEW_SKIP_RANGE=">=${REPLACES_VERSION} <${NEW_VERSION_NUM}"
    fi

    # Update channel entry with name, skipRange, and preserve replaces
    yq '(.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries[] | select(.name == "'"$OLD_BUNDLE_NAME"'")) |= (.name = "'"$NEW_BUNDLE_NAME"'" | .skipRange = "'"$NEW_SKIP_RANGE"'")' -i catalog-template.yaml

    echo "✓ Updated channel entry (skipRange: $NEW_SKIP_RANGE)"
  else
    # No replaces - first entry in channel
    NEW_SKIP_RANGE=">=${SKIPRANGE_BASE} <${NEW_VERSION_NUM}"

    yq '(.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries[] | select(.name == "'"$OLD_BUNDLE_NAME"'")) |= (.name = "'"$NEW_BUNDLE_NAME"'" | .skipRange = "'"$NEW_SKIP_RANGE"'")' -i catalog-template.yaml

    echo "✓ Updated channel entry (first in channel, skipRange: $NEW_SKIP_RANGE)"
  fi

  echo ""
}

#------------------------------------------------------------------------------
# verify_template - Check template has correct SHA
#------------------------------------------------------------------------------
verify_template() {
  echo "=== Verifying Template ==="

  cd "$REPO_ROOT"

  BUNDLE_NAME="submariner.v${VERSION}"

  # Verify bundle exists
  BUNDLE_IN_TEMPLATE=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "'"$BUNDLE_NAME"'")' catalog-template.yaml)
  if [ -z "$BUNDLE_IN_TEMPLATE" ]; then
    echo "✗ Bundle $BUNDLE_NAME not found in template"
    return 1
  fi
  echo "✓ Bundle entry exists"

  # Verify SHA matches
  TEMPLATE_IMAGE=$(yq '.entries[] | select(.schema == "olm.bundle" and .name == "'"$BUNDLE_NAME"'").image' catalog-template.yaml)
  TEMPLATE_SHA=$(echo "$TEMPLATE_IMAGE" | grep -oP 'sha256:\K[a-f0-9]+')

  if [ "$TEMPLATE_SHA" != "$BUNDLE_SHA" ]; then
    echo "✗ SHA mismatch!"
    echo "  Expected: ${BUNDLE_SHA:0:12}..."
    echo "  Template: ${TEMPLATE_SHA:0:12}..."
    return 1
  fi
  echo "✓ SHA matches snapshot"

  # Verify bundle in channel
  CHANNEL="stable-${YSTREAM}"
  IN_CHANNEL=$(yq '.entries[] | select(.schema == "olm.channel" and .name == "'"$CHANNEL"'").entries[] | select(.name == "'"$BUNDLE_NAME"'")' catalog-template.yaml)

  if [ -z "$IN_CHANNEL" ]; then
    echo "✗ Bundle not found in channel $CHANNEL"
    return 1
  fi
  echo "✓ Bundle exists in channel $CHANNEL"
  echo ""
}

#------------------------------------------------------------------------------
# verify_catalogs - Check all 8 OCP catalogs rebuilt with correct SHA
#------------------------------------------------------------------------------
verify_catalogs() {
  echo "=== Verifying Generated Catalogs ==="

  cd "$REPO_ROOT"

  FAILED=0

  # Check each OCP version (currently 4-14 through 4-21, but use dynamic detection)
  for CATALOG_DIR in catalog-*/; do
    if [ ! -d "$CATALOG_DIR" ]; then
      continue
    fi

    BUNDLE_FILE="${CATALOG_DIR}bundles/bundle-v${VERSION}.yaml"

    # Check if bundle file exists (might not exist in older OCP versions due to pruning)
    if [ ! -f "$BUNDLE_FILE" ]; then
      # This is OK - older OCP versions prune old bundles
      continue
    fi

    # Verify SHA in generated bundle
    CATALOG_SHA=$(grep "^image:" "$BUNDLE_FILE" | head -1 | grep -oP 'sha256:\K[a-f0-9]+' || echo "")

    if [ -z "$CATALOG_SHA" ]; then
      echo "✗ Could not extract SHA from $BUNDLE_FILE"
      ((FAILED++))
      continue
    fi

    if [ "$CATALOG_SHA" != "$BUNDLE_SHA" ]; then
      echo "✗ SHA mismatch in $BUNDLE_FILE"
      echo "  Expected: ${BUNDLE_SHA:0:12}..."
      echo "  Catalog:  ${CATALOG_SHA:0:12}..."
      ((FAILED++))
      continue
    fi

    echo "✓ $CATALOG_DIR contains bundle with correct SHA"
  done

  if [ $FAILED -gt 0 ]; then
    echo ""
    echo "✗ $FAILED catalog(s) failed verification"
    return 1
  fi

  echo "✓ All catalogs verified"
  echo ""
}

#------------------------------------------------------------------------------
# verify_opm - Run opm validation on all catalogs
#------------------------------------------------------------------------------
verify_opm() {
  echo "=== Running opm Validation ==="

  cd "$REPO_ROOT"

  # Ensure opm is installed
  if ! make opm >/dev/null 2>&1; then
    echo "✗ opm installation failed"
    return 1
  fi

  FAILED=0

  for CATALOG_DIR in catalog-*/; do
    if [ ! -d "$CATALOG_DIR" ]; then
      continue
    fi

    if ./bin/opm validate "$CATALOG_DIR" >/dev/null 2>&1; then
      echo "✓ $CATALOG_DIR valid"
    else
      echo "✗ Validation failed: $CATALOG_DIR"
      ./bin/opm validate "$CATALOG_DIR" 2>&1 || true
      ((FAILED++))
    fi
  done

  if [ $FAILED -gt 0 ]; then
    echo ""
    echo "✗ $FAILED catalog(s) failed opm validation"
    return 1
  fi

  echo "✓ All catalogs valid"
  echo ""
}

#------------------------------------------------------------------------------
# create_commit - Generate commit with metadata
#------------------------------------------------------------------------------
create_commit() {
  echo "=== Creating Commit ==="

  cd "$REPO_ROOT"

  # Determine commit message based on scenario
  case "$SCENARIO" in
    ADD)
      COMMIT_TITLE="Add bundle v$VERSION to catalog"
      SCENARIO_DESC="ADD (new Y-stream)"
      ;;
    UPDATE)
      COMMIT_TITLE="Update bundle v$VERSION SHA"
      SCENARIO_DESC="UPDATE (rebuild)"
      ;;
    REPLACE)
      COMMIT_TITLE="Replace bundle v$REPLACE with v$VERSION"
      SCENARIO_DESC="REPLACE (skip version)"
      ;;
    *)
      echo "ERROR: Unknown scenario: $SCENARIO"
      return 1
      ;;
  esac

  # Build commit message
  COMMIT_MSG="$COMMIT_TITLE

Scenario: $SCENARIO_DESC
Snapshot: $SNAPSHOT
Bundle: sha256:${BUNDLE_SHA:0:12}..."

  if [ "$SCENARIO" = "REPLACE" ]; then
    COMMIT_MSG="$COMMIT_MSG
Replaces: v$REPLACE"
  fi

  COMMIT_MSG="$COMMIT_MSG

Generated by:
    make update-bundle VERSION=$VERSION"

  [ -n "$SNAPSHOT" ] && COMMIT_MSG="$COMMIT_MSG SNAPSHOT=$SNAPSHOT"
  [ -n "$REPLACE" ] && COMMIT_MSG="$COMMIT_MSG REPLACE=$REPLACE"

  # Stage changes
  echo "Staging changes..."
  git add catalog-template.yaml catalog-*/ 2>/dev/null || true

  # Stage .tekton if it changed (ADD scenario updates image mirror set)
  if [ -f .tekton/images-mirror-set.yaml ] && ! git diff --quiet .tekton/images-mirror-set.yaml 2>/dev/null; then
    git add .tekton/images-mirror-set.yaml
  fi

  # Create commit
  echo "Committing..."
  git commit -m "$COMMIT_MSG" --signoff

  echo "✓ Commit created"
  echo ""
}

#------------------------------------------------------------------------------
# main - Orchestrate full workflow
#------------------------------------------------------------------------------
main() {
  parse_args "$@"

  echo "=== FBC Bundle Update ==="
  echo "Version: $VERSION"
  [ -n "$REPLACE" ] && echo "Replace: $REPLACE"
  echo ""

  # Change to repo root
  cd "$REPO_ROOT"

  # Step 1: Find snapshot and extract bundle image
  find_snapshot

  # Step 2: Detect scenario
  detect_scenario

  # Step 2.5: Audit bundle URLs and optionally convert
  audit_bundle_urls

  if [ "$AUTO_CONVERT" = true ]; then
    convert_released_bundles
  fi

  # Step 3: Update catalog-template.yaml based on scenario
  case "$SCENARIO" in
    ADD)
      update_template_add
      ;;
    UPDATE)
      update_template_update
      ;;
    REPLACE)
      update_template_replace
      ;;
    *)
      echo "ERROR: Unknown scenario: $SCENARIO"
      exit 1
      ;;
  esac

  # Step 4: Rebuild catalogs
  echo "=== Rebuilding Catalogs ==="
  make build-catalogs
  echo ""

  # Step 5: Format YAML
  echo "=== Formatting YAML ==="
  ./scripts/format-yaml.sh
  echo ""

  # Step 6: Verify update
  if ! verify_template; then
    echo "✗ Template verification failed"
    exit 1
  fi

  if ! verify_catalogs; then
    echo "✗ Catalog verification failed"
    exit 1
  fi

  if ! verify_opm; then
    echo "✗ OPM validation failed"
    exit 1
  fi

  # Step 7: Create commit
  if ! create_commit; then
    echo "✗ Commit creation failed"
    exit 1
  fi

  # Success!
  echo "✅ Update complete!"
  echo ""
  echo "Next steps:"
  echo "  1. Review commit: git show"
  echo "  2. Push changes: git push origin \$(git rev-parse --abbrev-ref HEAD)"
  echo "  3. Create PR if needed: gh pr create"
  echo ""
}

# Execute main
main "$@"
