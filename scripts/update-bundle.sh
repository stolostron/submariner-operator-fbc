#!/bin/bash
#
# update-bundle.sh - Automate FBC catalog updates for Submariner releases
#
# Usage: ./scripts/update-bundle.sh --version X.Y.Z [--snapshot name] [--replace X.Y.Z] [--auto-convert]
#
# Prerequisites:
#   - oc login to Konflux cluster (https://api.kflux-prd-rh02.0fk9.p1.openshiftapps.com:6443/)
#   - Disconnect from RH VPN (blocks registry.redhat.io access)
#   - Run from repo root: cd ~/konflux/submariner-operator-fbc
#
# Examples:
#   # UPDATE: Z-stream rebuild (most common - 0.21.1 → 0.21.2)
#   make update-bundle VERSION=0.21.2
#
#   # ADD: New Y-stream (0.21 → 0.22.0)
#   make update-bundle VERSION=0.22.0
#
#   # REPLACE: Skip broken version (release 0.21.2 instead of 0.21.1)
#   make update-bundle VERSION=0.21.2 REPLACE=0.21.1
#
#   # Explicit snapshot (rarely needed - script auto-finds latest passing)
#   make update-bundle VERSION=0.21.2 SNAPSHOT=submariner-0-21-abc123
#
#   # Convert old quay.io bundles to registry.redhat.io (maintenance)
#   make update-bundle VERSION=0.21.2 AUTO_CONVERT=true
#
# Scenarios (auto-detected):
#   UPDATE: Version exists in catalog, rebuild with new SHA
#   ADD: Version doesn't exist, add new bundle + channel entry
#   REPLACE: Replace version X with Y (skips X in upgrade path)
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
# Minimum version for skipRange - establishes upgrade path floor for new channels
# Used when creating first entry in new channel to prevent OLM from attempting
# upgrades from unsupported pre-0.18 versions
SKIPRANGE_BASE="0.18.0"

#------------------------------------------------------------------------------
# Library Imports
#------------------------------------------------------------------------------

# Source catalog manipulation functions
source "${SCRIPT_DIR}/lib/catalog-functions.sh"

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

# Update bundle image in catalog template
# Parameters: $1 = bundle name, $2 = new image URL
# Side effects: Modifies catalog-template.yaml
update_bundle_image() {
  local bundle_name="$1" new_image="$2"
  [ -z "$bundle_name" ] && return 1
  [ -z "$new_image" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  BUNDLE_NAME="$bundle_name" NEW_IMAGE="$new_image" yq eval '(.entries[] | select(.schema == "olm.bundle" and .name == env(BUNDLE_NAME)) | .image) = env(NEW_IMAGE)' -i catalog-template.yaml
}

# Add bundle entry to catalog template
# Parameters: $1 = bundle name, $2 = bundle image
# Side effects: Modifies catalog-template.yaml
add_bundle_entry() {
  local bundle_name="$1" bundle_image="$2"
  if ! BUNDLE_NAME="$bundle_name" BUNDLE_IMAGE="$bundle_image" yq eval '.entries += [{"name": env(BUNDLE_NAME), "image": env(BUNDLE_IMAGE), "schema": "olm.bundle"}]' -i catalog-template.yaml; then
    echo "ERROR: Failed to add bundle entry $bundle_name"
    return 1
  fi
}

# Ensure channel exists with proper mirrors for new Y-stream
# Parameters: $1 = channel name, $2 = Y-stream version with dash (e.g., "0-23")
# Side effects: Creates channel if needed, updates defaultChannel, updates image mirrors
ensure_channel_with_mirrors() {
  local channel_name="$1" ystream_dash="$2"

  if ! channel_exists "$channel_name"; then
    echo "Creating new channel: $channel_name"
    if ! CHANNEL_NAME="$channel_name" yq eval '.entries += [{"name": env(CHANNEL_NAME), "package": "submariner", "schema": "olm.channel", "entries": []}]' -i catalog-template.yaml; then
      echo "ERROR: Failed to create channel $channel_name"
      return 1
    fi

    echo "Updating defaultChannel to $channel_name..."
    if ! CHANNEL_NAME="$channel_name" yq eval '(.entries[] | select(.schema == "olm.package") | .defaultChannel) = env(CHANNEL_NAME)' -i catalog-template.yaml; then
      echo "ERROR: Failed to update defaultChannel to $channel_name"
      return 1
    fi
    echo "✓ Created channel and updated defaultChannel"

    echo "Updating image mirror set for new Y-stream..."
    if [ -f .tekton/images-mirror-set.yaml ]; then
      # Extract previous Y-stream from existing mirror entries
      local prev_ystream_dash
      prev_ystream_dash=$(grep -oP 'lighthouse-agent-\K[0-9]+-[0-9]+' .tekton/images-mirror-set.yaml | head -1)

      if [ -n "$prev_ystream_dash" ]; then
        # Check for unreleased bundles from previous Y-stream before updating mirrors
        local old_ystream_bundles
        old_ystream_bundles=$(BUNDLE_PATTERN="submariner-bundle-${prev_ystream_dash}" yq eval '.entries[] | select(.schema == "olm.bundle" and (.image | contains(env(BUNDLE_PATTERN))))' catalog-template.yaml)

        if [ -n "$old_ystream_bundles" ]; then
          echo ""
          echo "⚠️  WARNING: Found unreleased bundles using -${prev_ystream_dash} mirrors:"
          echo "$old_ystream_bundles" | yq '.name' | sed 's/^/   - /'
          echo ""
          echo "   These bundles will lose mirror access after updating to -${ystream_dash}"
          echo "   Options:"
          echo "     1. Remove unreleased bundles from catalog (recommended if never releasing)"
          echo "     2. Convert to registry.redhat.io if released (use --auto-convert)"
          echo "     3. Keep both mirror versions (will accumulate old versions)"
          echo ""
          echo "   Press Enter to continue or wait 5 seconds (Ctrl-C to abort)..."
          read -r -t 5 || true
          echo ""
        fi

        # Replace all component version suffixes
        # Verify file exists and changes will be made before modifying
        if ! grep -q -- "-${prev_ystream_dash}" .tekton/images-mirror-set.yaml; then
          echo "⚠️  WARNING: No -${prev_ystream_dash} entries found in images-mirror-set.yaml"
          echo "   File may already be updated or have unexpected format"
        else
          sed -i "s|-${prev_ystream_dash}|-${ystream_dash}|g" .tekton/images-mirror-set.yaml
          echo "✓ Updated image mirror set: -$prev_ystream_dash → -$ystream_dash"
        fi
      else
        echo "⚠️  WARNING: Could not detect previous Y-stream version in .tekton/images-mirror-set.yaml"
        echo "   Manually update component version suffixes to -$ystream_dash"
      fi
    else
      echo "⚠️  WARNING: .tekton/images-mirror-set.yaml not found"
    fi
  else
    echo "Channel $channel_name already exists"
  fi
}

# Add bundle to channel (first or subsequent entry)
# Parameters: $1 = bundle name, $2 = channel name, $3 = version, $4 = skiprange base
# Side effects: Modifies catalog-template.yaml
add_bundle_to_channel() {
  local bundle_name="$1" channel_name="$2" version="$3" skiprange_base="$4"

  local entries_in_channel
  entries_in_channel=$(get_channel_entry_count "$channel_name")

  if [ -z "$entries_in_channel" ]; then
    echo "ERROR: Could not determine channel entry count for $channel_name"
    exit 1
  fi

  # Validate entry count is numeric (prevents cryptic -eq errors)
  if ! [[ "$entries_in_channel" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid channel entry count '$entries_in_channel' (expected numeric)"
    exit 1
  fi

  if [ "$entries_in_channel" -eq 0 ]; then
    # First entry in channel (no replaces)
    echo "Adding as first entry in channel (no replaces)..."
    # Use jq workaround for yq += bug with complex YAML structures
    yq eval -o=json '.' catalog-template.yaml | \
      jq --arg channel "$channel_name" --arg bundle "$bundle_name" --arg skip ">=${skiprange_base} <${version}" \
        '(.entries[] | select(.schema == "olm.channel" and .name == $channel) | .entries) += [{name: $bundle, skipRange: $skip}]' | \
      yq eval -P '.' - > catalog-template.yaml.tmp && mv catalog-template.yaml.tmp catalog-template.yaml
    echo "✓ Added first entry to channel $channel_name"
  else
    # Subsequent entry (with replaces)
    local replaces_bundle_name
    replaces_bundle_name=$(get_latest_channel_entry "$channel_name")

    if [ -z "$replaces_bundle_name" ]; then
      echo "ERROR: Could not determine bundle to replace in channel $channel_name"
      exit 1
    fi

    local replaces_version="${replaces_bundle_name#submariner.v}"

    echo "Adding with replaces: $replaces_bundle_name"
    # Use jq workaround for yq += bug with complex YAML structures
    yq eval -o=json '.' catalog-template.yaml | \
      jq --arg channel "$channel_name" --arg bundle "$bundle_name" --arg replaces "$replaces_bundle_name" --arg skip ">=${replaces_version} <${version}" \
        '(.entries[] | select(.schema == "olm.channel" and .name == $channel) | .entries) += [{name: $bundle, replaces: $replaces, skipRange: $skip}]' | \
      yq eval -P '.' - > catalog-template.yaml.tmp && mv catalog-template.yaml.tmp catalog-template.yaml
    echo "✓ Added entry to channel $channel_name (skipRange: >=${replaces_version} <${version})"
  fi
}

# Get bundle entry from channel
# Parameters: $1 = channel name, $2 = bundle name
# Returns: Channel entry YAML, or empty if not found
get_channel_bundle_entry() {
  local channel_name="$1" bundle_name="$2"
  [ -z "$channel_name" ] && return 1
  [ -z "$bundle_name" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  CHANNEL_NAME="$channel_name" BUNDLE_NAME="$bundle_name" yq eval '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL_NAME)) | .entries[] | select(.name == env(BUNDLE_NAME))' catalog-template.yaml
}

#------------------------------------------------------------------------------
# parse_args - Parse command-line arguments
#------------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --version)
        [ $# -lt 2 ] && { echo "ERROR: --version requires an argument"; exit 1; }
        VERSION="$2"; shift 2 ;;
      --snapshot)
        [ $# -lt 2 ] && { echo "ERROR: --snapshot requires an argument"; exit 1; }
        SNAPSHOT="$2"; shift 2 ;;
      --replace)
        [ $# -lt 2 ] && { echo "ERROR: --replace requires an argument"; exit 1; }
        REPLACE="$2"; shift 2 ;;
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
  if ! validate_version_format "$VERSION"; then
    echo "ERROR: Invalid version format '$VERSION' (expected X.Y.Z, e.g., 0.22.1)"
    exit 1
  fi

  # Validate REPLACE version format if provided
  if [ -n "$REPLACE" ] && ! validate_version_format "$REPLACE"; then
    echo "ERROR: Invalid REPLACE version format '$REPLACE' (expected X.Y.Z, e.g., 0.22.0)"
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

    # Filter to push events only (PR snapshots fail EC quay_expiration policy)
    SNAPSHOT=$(oc get snapshots -n submariner-tenant --sort-by=.metadata.creationTimestamp \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.pac\.test\.appstudio\.openshift\.io/event-type}{"\n"}{end}' \
      | grep "^submariner-$YSTREAM_DASH.*push$" \
      | tail -1 \
      | awk '{print $1}')

    if [ -z "$SNAPSHOT" ]; then
      echo "ERROR: No push-event snapshot found for version $YSTREAM_DASH"
      echo ""
      echo "Expected pattern: submariner-$YSTREAM_DASH-XXXXX (from push events)"
      echo ""
      echo "Available push snapshots (recent):"
      oc get snapshots -n submariner-tenant --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.pac\.test\.appstudio\.openshift\.io/event-type}{"\n"}{end}' \
        | grep "^submariner-.*push$" | tail -5
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

  # Verify snapshot tests passed
  echo "Verifying snapshot tests..."
  TEST_STATUS=$(oc get snapshot "$SNAPSHOT" -n submariner-tenant \
    -o jsonpath='{.metadata.annotations.test\.appstudio\.openshift\.io/status}')

  if [ -z "$TEST_STATUS" ]; then
    echo "ERROR: Snapshot $SNAPSHOT has no test status (may still be building)"
    exit 1
  fi

  # Validate TEST_STATUS is valid JSON before parsing
  if ! echo "$TEST_STATUS" | jq empty 2>/dev/null; then
    echo "ERROR: Invalid test status JSON in snapshot $SNAPSHOT"
    echo "Raw status: $TEST_STATUS"
    exit 1
  fi

  FAILED_TESTS=$(echo "$TEST_STATUS" | jq -r '.[] | select(.status != "TestPassed") | .scenario' 2>/dev/null || true)
  if [ -n "$FAILED_TESTS" ]; then
    echo "ERROR: Snapshot $SNAPSHOT has failing tests:"
    echo "$TEST_STATUS" | jq -r '.[] | "\(.scenario): \(.status)"'
    exit 1
  fi
  echo "✓ All tests passed"

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
  BUNDLE_SHA=$(extract_sha "$BUNDLE_IMAGE")
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

  BUNDLE_NAME="submariner.v${VERSION}"
  CHANNEL="stable-${YSTREAM}"

  # Batch query: get bundle and channel data in single yq call
  CATALOG_DATA=$(BUNDLE_NAME="$BUNDLE_NAME" CHANNEL_NAME="$CHANNEL" yq eval -o json '{
    "bundle": (.entries[] | select(.schema == "olm.bundle" and .name == env(BUNDLE_NAME)) | .name),
    "channel": (.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL_NAME)) | .entries[] | select(.name == env(BUNDLE_NAME)) | .name)
  }' catalog-template.yaml)

  BUNDLE_EXISTS=$(echo "$CATALOG_DATA" | jq -r '.bundle // ""')
  CHANNEL_EXISTS=$(echo "$CATALOG_DATA" | jq -r '.channel // ""')

  # Scenario detection logic
  if [ -n "$REPLACE" ]; then
    # User explicitly requested REPLACE scenario - need old bundle check
    OLD_BUNDLE_NAME="submariner.v${REPLACE}"
    OLD_BUNDLE_EXISTS=$(get_bundle_entry "$OLD_BUNDLE_NAME")

    if [ -z "$OLD_BUNDLE_EXISTS" ]; then
      echo "ERROR: Cannot replace - version $REPLACE not found in catalog"
      echo ""
      echo "Available bundles:"
      yq eval '.entries[] | select(.schema == "olm.bundle") | .name' catalog-template.yaml | grep submariner.v | tail -10
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

  # Verify catalog-template.yaml exists before querying
  if [ ! -f "catalog-template.yaml" ]; then
    echo "ERROR: catalog-template.yaml not found"
    exit 1
  fi

  UNRELEASED_BUNDLES=()  # Global arrays for convert_released_bundles()
  CONVERTIBLE_BUNDLES=()

  # Find all quay.io bundles
  local QUAY_BUNDLES
  QUAY_BUNDLES=$(yq '.entries[] | select(.schema == "olm.bundle" and (.image | contains("quay.io"))) | {"name": .name, "image": .image}' catalog-template.yaml -o json | jq -c '.')

  if [ -z "$QUAY_BUNDLES" ]; then
    echo "✓ No quay.io bundles found (all use registry.redhat.io)"
    echo ""
    return 0
  fi

  while IFS= read -r bundle; do
    [ -z "$bundle" ] && continue
    local name
    local image
    local sha
    name=$(echo "$bundle" | jq -r '.name')
    image=$(echo "$bundle" | jq -r '.image')
    sha=$(extract_sha "$image")

    if [ -z "$sha" ]; then
      echo "⚠️  WARNING: Could not extract SHA from: $image"
      continue
    fi

    # Check if bundle exists at registry.redhat.io
    local prod_image="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:$sha"

    # Check if image exists (timeout returns 124, other failures return non-zero)
    # Use 30s timeout (registry should respond faster, prevents false negatives on slow networks)
    # Capture exit code without triggering set -e
    local exit_code=0
    timeout 30 skopeo inspect "docker://$prod_image" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -eq 0 ]; then
      echo "⚠️  $name: RELEASED but using quay.io URL"
      echo "   Current:  $image"
      echo "   Available: $prod_image"
      CONVERTIBLE_BUNDLES+=("$name")
    elif [ $exit_code -eq 124 ]; then
      echo "⚠️  $name: TIMEOUT checking registry.redhat.io (network issue?)"
      echo "   Skipping conversion - cannot verify release status"
      # Don't add to UNRELEASED_BUNDLES - timeout is indeterminate
    else
      echo "ℹ️  $name: UNRELEASED (quay.io workspace URL)"
      UNRELEASED_BUNDLES+=("$name")
    fi
  done <<< "$QUAY_BUNDLES"
  
  echo ""
  echo "Summary: $((${#CONVERTIBLE_BUNDLES[@]} + ${#UNRELEASED_BUNDLES[@]})) quay.io bundle(s) - ${#CONVERTIBLE_BUNDLES[@]} convertible, ${#UNRELEASED_BUNDLES[@]} unreleased"
  
  if [ ${#CONVERTIBLE_BUNDLES[@]} -gt 0 ]; then
    if [ "$AUTO_CONVERT" = true ]; then
      echo "🔄 Auto-convert enabled - will convert released bundles"
    else
      echo "💡 Tip: Use --auto-convert to automatically convert released bundles"
    fi
  fi
  
  echo ""
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

  local FAILED=0

  for name in "${CONVERTIBLE_BUNDLES[@]}"; do
    # Get current image
    local current_image
    local sha
    local new_image
    current_image=$(get_bundle_image "$name")

    if [ -z "$current_image" ]; then
      echo "✗ ERROR: Bundle $name not found in catalog-template.yaml"
      FAILED=$((FAILED + 1))
      continue
    fi

    sha=$(extract_sha "$current_image")

    if [ -z "$sha" ]; then
      echo "✗ ERROR: Could not extract SHA from bundle $name image: $current_image"
      FAILED=$((FAILED + 1))
      continue
    fi

    new_image="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:$sha"

    # Update template
    if ! update_bundle_image "$name" "$new_image"; then
      echo "✗ ERROR: Failed to update bundle image for $name"
      FAILED=$((FAILED + 1))
      continue
    fi

    echo "✓ $name: quay.io → registry.redhat.io"
  done

  if [ $FAILED -gt 0 ]; then
    echo "✗ $FAILED bundle(s) failed conversion"
    return 1
  fi

  echo "✓ Converted ${#CONVERTIBLE_BUNDLES[@]} bundle(s)"
  echo ""
}


#------------------------------------------------------------------------------
# update_template_add - ADD scenario: new channel + bundle
#------------------------------------------------------------------------------
update_template_add() {
  echo "=== Adding New Bundle ==="

  local bundle_name="submariner.v${VERSION}"
  local channel="stable-${YSTREAM}"

  # Phase 1: Add bundle entry
  echo "Adding bundle entry..."
  add_bundle_entry "$bundle_name" "$BUNDLE_IMAGE"
  echo "✓ Added bundle entry: $bundle_name"

  # Phase 2: Ensure channel exists with proper mirrors
  ensure_channel_with_mirrors "$channel" "$YSTREAM_DASH"

  # Phase 3: Add bundle to channel
  add_bundle_to_channel "$bundle_name" "$channel" "$VERSION" "$SKIPRANGE_BASE"

  echo ""
}

#------------------------------------------------------------------------------
# update_template_update - UPDATE scenario: SHA replacement
#------------------------------------------------------------------------------
update_template_update() {
  echo "=== Updating Bundle SHA ==="

  BUNDLE_NAME="submariner.v${VERSION}"

  # Get current image to show diff
  CURRENT_IMAGE=$(get_bundle_image "$BUNDLE_NAME")
  CURRENT_SHA=$(extract_sha "$CURRENT_IMAGE")
  [ -z "$CURRENT_SHA" ] && CURRENT_SHA="unknown"

  echo "Current SHA: ${CURRENT_SHA:0:12}..."
  echo "New SHA:     ${BUNDLE_SHA:0:12}..."

  if [ "$CURRENT_SHA" = "$BUNDLE_SHA" ]; then
    echo "⚠️  WARNING: SHA unchanged - bundle already at this version"
    echo "Proceeding anyway to rebuild catalogs..."
  fi

  # Update image SHA in catalog-template.yaml
  echo "Updating bundle image..."
  update_bundle_image "$BUNDLE_NAME" "$BUNDLE_IMAGE"

  echo "✓ Updated $BUNDLE_NAME SHA in catalog-template.yaml"
  echo ""
}

#------------------------------------------------------------------------------
# update_template_replace - REPLACE scenario: rename entries
#------------------------------------------------------------------------------
update_template_replace() {
  echo "=== Replacing Bundle Version ==="

  OLD_BUNDLE_NAME="submariner.v${REPLACE}"
  NEW_BUNDLE_NAME="submariner.v${VERSION}"
  CHANNEL="stable-${YSTREAM}"

  echo "Replacing: $OLD_BUNDLE_NAME → $NEW_BUNDLE_NAME"

  # Get old bundle image to show diff
  OLD_IMAGE=$(get_bundle_image "$OLD_BUNDLE_NAME")
  OLD_SHA=$(extract_sha "$OLD_IMAGE")
  [ -z "$OLD_SHA" ] && OLD_SHA="unknown"

  echo "Old SHA: ${OLD_SHA:0:12}..."
  echo "New SHA: ${BUNDLE_SHA:0:12}..."

  # Update bundle entry - rename and update image
  echo "Updating bundle entry..."

  # First update the name
  OLD_NAME="$OLD_BUNDLE_NAME" NEW_NAME="$NEW_BUNDLE_NAME" yq eval '(.entries[] | select(.schema == "olm.bundle" and .name == env(OLD_NAME)) | .name) = env(NEW_NAME)' -i catalog-template.yaml

  # Then update the image
  update_bundle_image "$NEW_BUNDLE_NAME" "$BUNDLE_IMAGE"

  echo "✓ Updated bundle entry"

  # Update channel entry - rename and update skipRange
  echo "Updating channel entry..."

  # Query channel entry once and extract both replaces and skipRange
  export CHANNEL_NAME="$CHANNEL"
  export BUNDLE_NAME="$OLD_BUNDLE_NAME"
  OLD_CHANNEL_ENTRY=$(yq eval '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL_NAME)) | .entries[] | select(.name == env(BUNDLE_NAME)) | {"replaces": (.replaces // ""), "skipRange": .skipRange}' -o json catalog-template.yaml)
  unset CHANNEL_NAME BUNDLE_NAME

  if [ -z "$OLD_CHANNEL_ENTRY" ]; then
    echo "ERROR: Channel entry for $OLD_BUNDLE_NAME not found in $CHANNEL"
    exit 1
  fi

  # Extract replaces value
  REPLACES_VALUE=$(echo "$OLD_CHANNEL_ENTRY" | jq -r '.replaces')

  # Determine skipRange based on whether this replaces another version
  # Preserve skipRange base to maintain OLM upgrade path continuity
  if [ -n "$REPLACES_VALUE" ] && [ "$REPLACES_VALUE" != "null" ]; then
    # Has replaces - prefer skipRange from old entry, fallback to replaces version
    SKIP_BASE=$(echo "$OLD_CHANNEL_ENTRY" | jq -r '.skipRange' | grep -oP '>=\K[0-9.]+' || true)

    if [ -z "$SKIP_BASE" ]; then
      # No skipRange on old entry - extract version from replaces field as fallback
      # Note: OLM doesn't strictly require skipRange, so this is a valid catalog state
      SKIP_BASE="${REPLACES_VALUE#submariner.v}"
      echo "⚠️  WARNING: Old version has 'replaces' but no skipRange"
      echo "   Using replaces version as base: $SKIP_BASE"
    fi

    NEW_SKIP_RANGE=">=${SKIP_BASE} <${VERSION}"
  else
    # No replaces - first entry in channel
    NEW_SKIP_RANGE=">=${SKIPRANGE_BASE} <${VERSION}"
  fi

  # Update channel entry with new name and skipRange (preserves replaces if present)
  # Use jq workaround for yq |= bug with complex YAML structures
  yq eval -o=json '.' catalog-template.yaml | \
    jq --arg channel "$CHANNEL" --arg old_name "$OLD_BUNDLE_NAME" --arg new_name "$NEW_BUNDLE_NAME" --arg skip "$NEW_SKIP_RANGE" \
      '(.entries[] | select(.schema == "olm.channel" and .name == $channel) | .entries[] | select(.name == $old_name)) |= (.name = $new_name | .skipRange = $skip)' | \
    yq eval -P '.' - > catalog-template.yaml.tmp && mv catalog-template.yaml.tmp catalog-template.yaml

  echo "✓ Updated channel entry (skipRange: $NEW_SKIP_RANGE)"

  echo ""
}

#------------------------------------------------------------------------------
# verify_template - Check template has correct SHA
#------------------------------------------------------------------------------
verify_template() {
  echo "=== Verifying Template ==="

  local BUNDLE_NAME="submariner.v${VERSION}"
  local CHANNEL="stable-${YSTREAM}"

  # Query bundle image and channel data separately (yq JSON object construction is unreliable)
  export BUNDLE_NAME
  export CHANNEL_NAME="$CHANNEL"
  TEMPLATE_IMAGE=$(yq eval '.entries[] | select(.schema == "olm.bundle" and .name == env(BUNDLE_NAME)) | .image' catalog-template.yaml)
  IN_CHANNEL=$(yq eval '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL_NAME)) | .entries[] | select(.name == env(BUNDLE_NAME)) | .name' catalog-template.yaml)

  # Verify bundle exists
  if [ -z "$TEMPLATE_IMAGE" ]; then
    echo "✗ Bundle $BUNDLE_NAME not found in template"
    return 1
  fi
  echo "✓ Bundle entry exists"

  # Verify SHA matches
  TEMPLATE_SHA=$(extract_sha "$TEMPLATE_IMAGE")

  if [ "$TEMPLATE_SHA" != "$BUNDLE_SHA" ]; then
    echo "✗ SHA mismatch!"
    echo "  Expected: ${BUNDLE_SHA:0:12}..."
    echo "  Template: ${TEMPLATE_SHA:0:12}..."
    return 1
  fi
  echo "✓ SHA matches snapshot"

  # Verify registry domain matches expected source
  EXPECTED_REGISTRY="${BUNDLE_IMAGE%%@sha256:*}"
  TEMPLATE_REGISTRY="${TEMPLATE_IMAGE%%@sha256:*}"
  if [ "$EXPECTED_REGISTRY" != "$TEMPLATE_REGISTRY" ]; then
    echo "✗ Registry domain mismatch!"
    echo "  Expected: $EXPECTED_REGISTRY"
    echo "  Template: $TEMPLATE_REGISTRY"
    return 1
  fi
  echo "✓ Registry matches snapshot"

  # Verify bundle in channel
  if [ -z "$IN_CHANNEL" ]; then
    echo "✗ Bundle not found in channel $CHANNEL"
    unset BUNDLE_NAME CHANNEL_NAME
    return 1
  fi
  echo "✓ Bundle exists in channel $CHANNEL"
  echo ""

  unset BUNDLE_NAME CHANNEL_NAME
}

#------------------------------------------------------------------------------
# verify_catalogs - Check all 8 OCP catalogs rebuilt with correct SHA
#------------------------------------------------------------------------------
verify_catalogs() {
  echo "=== Verifying Generated Catalogs ==="

  FAILED=0
  VERIFIED=0
  SKIPPED=0

  # Check each OCP version (currently 4-14 through 4-21, but use dynamic detection)
  for CATALOG_DIR in catalog-*/; do
    if [ ! -d "$CATALOG_DIR" ]; then
      continue
    fi

    BUNDLE_FILE="${CATALOG_DIR}bundles/bundle-v${VERSION}.yaml"

    # Check if bundle file exists (might not exist in older OCP versions due to pruning)
    if [ ! -f "$BUNDLE_FILE" ]; then
      # This is OK - older OCP versions prune old bundles
      echo "  ${CATALOG_DIR%/} skipped (bundle not in version range)"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    # Verify SHA in generated bundle
    CATALOG_IMAGE=$(yq eval '.image' "$BUNDLE_FILE")

    if [ -z "$CATALOG_IMAGE" ] || [ "$CATALOG_IMAGE" = "null" ]; then
      echo "✗ Could not extract image from $BUNDLE_FILE"
      FAILED=$((FAILED + 1))
      continue
    fi

    CATALOG_SHA=$(extract_sha "$CATALOG_IMAGE")

    if [ -z "$CATALOG_SHA" ]; then
      echo "✗ Could not extract SHA from $BUNDLE_FILE (image: $CATALOG_IMAGE)"
      FAILED=$((FAILED + 1))
      continue
    fi

    if [ "$CATALOG_SHA" != "$BUNDLE_SHA" ]; then
      echo "✗ SHA mismatch in $BUNDLE_FILE"
      echo "  Expected: ${BUNDLE_SHA:0:12}..."
      echo "  Catalog:  ${CATALOG_SHA:0:12}..."
      FAILED=$((FAILED + 1))
      continue
    fi

    echo "✓ ${CATALOG_DIR%/} verified"
    VERIFIED=$((VERIFIED + 1))
  done

  echo ""
  if [ $FAILED -gt 0 ]; then
    echo "✗ $FAILED catalog(s) failed verification"
    return 1
  fi

  if [ $VERIFIED -eq 0 ]; then
    echo "✗ WARNING: No catalogs were verified (all skipped)"
    return 1
  fi

  echo "✓ All catalogs verified ($VERIFIED checked, $SKIPPED skipped)"
  echo ""
}

#------------------------------------------------------------------------------
# verify_opm - Run opm validation on all catalogs
#------------------------------------------------------------------------------
verify_opm() {
  echo "=== Running opm Validation ==="

  # Ensure opm is installed
  if ! make opm >/dev/null 2>&1; then
    echo "✗ opm installation failed"
    return 1
  fi

  # Verify binary exists after make
  if [ ! -x "./bin/opm" ]; then
    echo "✗ ERROR: opm binary not found at ./bin/opm after make"
    return 1
  fi

  FAILED=0
  VALIDATED=0

  for CATALOG_DIR in catalog-*/; do
    # Skip if glob didn't match any directories
    [ ! -d "$CATALOG_DIR" ] && continue

    OUTPUT=$(./bin/opm validate "$CATALOG_DIR" 2>&1)
    if [ $? -eq 0 ]; then
      echo "✓ ${CATALOG_DIR%/} valid"
      VALIDATED=$((VALIDATED + 1))
    else
      echo "✗ Validation failed: $CATALOG_DIR"
      echo "$OUTPUT"
      FAILED=$((FAILED + 1))
    fi
  done

  echo ""
  if [ $FAILED -gt 0 ]; then
    echo "✗ $FAILED catalog(s) failed opm validation"
    return 1
  fi

  echo "✓ All catalogs valid ($VALIDATED validated)"
  echo ""
}

#------------------------------------------------------------------------------
# create_commit - Generate commit with metadata
#------------------------------------------------------------------------------
create_commit() {
  echo "=== Creating Commit ==="

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

  # Stage changes
  echo "Staging changes..."
  if ! git add catalog-template.yaml catalog-*/ 2>/dev/null; then
    echo "✗ ERROR: Failed to stage catalog files"
    return 1
  fi

  # Stage .tekton if it changed (ADD scenario updates image mirror set)
  if [ -f ".tekton/images-mirror-set.yaml" ] && ! git diff --quiet ".tekton/images-mirror-set.yaml" 2>/dev/null; then
    if ! git add ".tekton/images-mirror-set.yaml"; then
      echo "✗ ERROR: Failed to stage .tekton/images-mirror-set.yaml"
      return 1
    fi
  fi

  # Verify we have changes to commit
  if git diff --cached --quiet; then
    echo "✗ ERROR: No changes staged for commit"
    return 1
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
    if ! convert_released_bundles; then
      echo "ERROR: Bundle conversion failed"
      exit 1
    fi
  fi

  # Step 3: Update catalog-template.yaml based on scenario
  case "$SCENARIO" in
    ADD)
      if ! update_template_add; then
        echo "ERROR: Failed to add bundle to catalog"
        exit 1
      fi
      ;;
    UPDATE)
      if ! update_template_update; then
        echo "ERROR: Failed to update bundle in catalog"
        exit 1
      fi
      ;;
    REPLACE)
      if ! update_template_replace; then
        echo "ERROR: Failed to replace bundle in catalog"
        exit 1
      fi
      ;;
    *)
      echo "ERROR: Unknown scenario: $SCENARIO"
      exit 1
      ;;
  esac

  # Step 4: Rebuild catalogs
  echo "=== Rebuilding Catalogs ==="
  if ! make build-catalogs; then
    echo "✗ ERROR: Catalog rebuild failed"
    exit 1
  fi
  echo ""

  # Step 5: Format YAML
  echo "=== Formatting YAML ==="
  if ! ./scripts/format-yaml.sh; then
    echo "✗ ERROR: YAML formatting failed"
    exit 1
  fi
  echo ""

  # Step 6: Verify update
  for verify_fn in verify_template verify_catalogs verify_opm; do
    if ! $verify_fn; then
      echo "✗ Verification failed: $verify_fn"
      exit 1
    fi
  done

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
