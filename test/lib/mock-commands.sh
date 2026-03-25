#!/bin/bash
# mock-commands.sh - Shared mock functions for integration tests

# Create oc mock for integration tests
# Parameters:
#   $1 = snapshot name (e.g., "submariner-0-24-xyz789")
#   $2 = bundle image URL with SHA256 digest
create_oc_mock() {
  # Store parameters in global variables for the mock to use
  MOCK_SNAPSHOT_NAME="$1"
  MOCK_BUNDLE_IMAGE="$2"
  export MOCK_SNAPSHOT_NAME MOCK_BUNDLE_IMAGE

  # Export function so subprocesses can see it
  export -f oc
}

# Mock oc function (uses MOCK_* globals set by create_oc_mock)
oc() {
  [[ "$1" != "get" ]] && return 1

  # Handle 'oc get snapshots'
  if [[ "$2" == "snapshots" ]]; then
    echo "${MOCK_SNAPSHOT_NAME}	push"
    return 0
  fi

  # Handle 'oc get snapshot <name>'
  [[ "$2" != "snapshot" ]] && return 1

  # Parse arguments
  shift 2
  local snapshot_arg="$1"
  shift
  local output_format=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -o) output_format="$2"; shift 2 ;;
      -n) shift 2 ;;
      *) shift ;;
    esac
  done

  # No output format: verify snapshot exists
  if [ -z "$output_format" ]; then
    [[ "$snapshot_arg" == "$MOCK_SNAPSHOT_NAME" ]] && return 0 || return 1
  fi

  # Output based on format
  case "$output_format" in
    *test*appstudio*)
      echo '[{"scenario":"submariner-fbc-4-20-operator","status":"TestPassed"}]'
      ;;
    jsonpath=*)
      echo "$MOCK_BUNDLE_IMAGE"
      ;;
  esac
}

# Setup mock binary directory and add to PATH
# Creates /tmp directory with mock binaries, sets up cleanup trap
# Returns: MOCK_BIN_DIR variable containing directory path
setup_mock_bin_dir() {
  # Use mktemp for safer temp directory creation
  MOCK_BIN_DIR=$(mktemp -d -t submariner-fbc-test-XXXXXX)
  export PATH="$MOCK_BIN_DIR:$PATH"
}

# Create skopeo mock
# Parameters:
#   $1 = exit code for bundle checks (0 = released, 1 = unreleased)
#   $2 = optional bundle pattern to check (e.g., "submariner-bundle-0-24")
create_skopeo_mock() {
  local exit_code="${1:-0}"
  local bundle_pattern="${2:-}"

  if [ -z "$MOCK_BIN_DIR" ]; then
    echo "ERROR: MOCK_BIN_DIR not set. Call setup_mock_bin_dir() first." >&2
    return 1
  fi

  if [ -n "$bundle_pattern" ]; then
    # Pattern-based mock: check if arguments contain pattern (fixed string match)
    cat > "$MOCK_BIN_DIR/skopeo" <<EOF
#!/bin/bash
if echo "\$@" | grep -qF "$bundle_pattern"; then
  exit $exit_code
else
  # Non-matching patterns: return 1 (image not found, consistent with real skopeo)
  exit 1
fi
EOF
  else
    # Simple mock: always return same exit code
    cat > "$MOCK_BIN_DIR/skopeo" <<EOF
#!/bin/bash
exit $exit_code
EOF
  fi

  chmod +x "$MOCK_BIN_DIR/skopeo"
}


# Cleanup mock functions and directories
cleanup_mocks() {
  # Unset mock functions
  unset -f oc 2>/dev/null || true

  # Unset mock environment variables
  unset MOCK_SNAPSHOT_NAME MOCK_BUNDLE_IMAGE 2>/dev/null || true

  # Remove mock binary directory and restore PATH
  if [ -n "${MOCK_BIN_DIR:-}" ] && [ -d "$MOCK_BIN_DIR" ]; then
    # Remove from start of PATH (where setup_mock_bin_dir added it)
    export PATH="${PATH#${MOCK_BIN_DIR}:}"
    rm -rf "$MOCK_BIN_DIR"
  fi

  # Unset the MOCK_BIN_DIR variable
  unset MOCK_BIN_DIR 2>/dev/null || true
}
