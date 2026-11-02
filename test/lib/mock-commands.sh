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
  MOCK_BUNDLE_VERSION="${3:?mock bundle version required}"
  export MOCK_SNAPSHOT_NAME MOCK_BUNDLE_IMAGE MOCK_BUNDLE_VERSION

  # Export function so subprocesses can see it
  export -f oc
}

# Mock oc function (uses MOCK_* globals set by create_oc_mock)
oc() {
  [[ "$1" == "get" ]] || return 1
  local object stream=${MOCK_BUNDLE_VERSION%.*}
  local default_status='[ {"scenario":"standard","status":"TestPassed"} ]'
  object=$(jq -n --arg name "$MOCK_SNAPSHOT_NAME" --arg image "$MOCK_BUNDLE_IMAGE" \
    --arg stream "${stream//./-}" --arg tests "${MOCK_TEST_STATUS-$default_status}" '
      {metadata: {name: $name, creationTimestamp: "2026-09-24T00:00:00Z",
                  labels: {"pac.test.appstudio.openshift.io/event-type": "push"},
                  annotations: {"test.appstudio.openshift.io/status": $tests}},
       spec: {application: ("submariner-" + $stream),
              components: [{name: ("submariner-bundle-" + $stream), containerImage: $image}]}}')
  if [[ "$2" == "snapshots" ]]; then
    jq -n --argjson object "$object" '{items: [$object]}'
  elif [[ "$2" == "snapshot" && "$3" == "$MOCK_SNAPSHOT_NAME" ]]; then
    echo "$object"
  else return 1; fi
}

# Setup mock binary directory and add to PATH
# Creates /tmp directory with mock binaries, sets up cleanup trap
# Returns: MOCK_BIN_DIR variable containing directory path
setup_mock_bin_dir() {
  # Use mktemp for safer temp directory creation
  MOCK_BIN_DIR=$(mktemp -d -t submariner-fbc-test-XXXXXX)
  export PATH="$MOCK_BIN_DIR:$PATH"
}

# Failures as printed by real skopeo 1.22 against registry.redhat.io
SKOPEO_ERR_MANIFEST_UNKNOWN='level=fatal msg="reading manifest sha256:0 in registry.redhat.io/rhacm2/submariner-operator-bundle: manifest unknown"'
SKOPEO_ERR_AUTH='level=fatal msg="unable to retrieve auth token: invalid username/password: unauthorized: Please login to the Red Hat Registry"'
SKOPEO_ERR_NETWORK='level=fatal msg="pinging container registry registry.redhat.io: dial tcp: lookup registry.redhat.io: no such host"'

# Create skopeo mock
# Parameters:
#   $1 = exit code for bundle checks (0 = released, 2 = manifest unknown, other = failure)
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
if [[ "\$*" == *--format* && "\$*" == *csv-version* ]]; then echo "\$MOCK_BUNDLE_VERSION"; exit 0; fi
if echo "\$@" | grep -qF "$bundle_pattern"; then
  [ $exit_code -ne 2 ] || echo '$SKOPEO_ERR_MANIFEST_UNKNOWN' >&2
  exit $exit_code
else
  # Non-matching patterns: image not found, consistent with real skopeo
  echo '$SKOPEO_ERR_MANIFEST_UNKNOWN' >&2
  exit 2
fi
EOF
  else
    # Simple mock: always return same exit code
    cat > "$MOCK_BIN_DIR/skopeo" <<EOF
#!/bin/bash
if [[ "\$*" == *--format* && "\$*" == *csv-version* ]]; then echo "\$MOCK_BUNDLE_VERSION"; exit 0; fi
[ $exit_code -ne 2 ] || echo '$SKOPEO_ERR_MANIFEST_UNKNOWN' >&2
exit $exit_code
EOF
  fi

  chmod +x "$MOCK_BIN_DIR/skopeo"
}

# Create skopeo mock that answers per digest. Digests not listed are absent.
# Parameters: "<sha>=<released|absent|timeout|auth|network|bare>" ...
#   bare = exit 1 with no output
create_skopeo_digest_mock() {
  local spec cases=""
  for spec in "$@"; do
    cases+="  *\"${spec%%=*}\"*) mode=${spec#*=} ;;"$'\n'
  done

  cat > "$MOCK_BIN_DIR/skopeo" <<EOF
#!/bin/bash
if [[ "\$*" == *--format* && "\$*" == *csv-version* ]]; then echo "\$MOCK_BUNDLE_VERSION"; exit 0; fi
mode=absent
case "\$*" in
$cases
esac
case "\$mode" in
  released) exit 0 ;;
  absent) echo '$SKOPEO_ERR_MANIFEST_UNKNOWN' >&2; exit 2 ;;
  timeout) exit 124 ;;
  auth) echo '$SKOPEO_ERR_AUTH' >&2; exit 1 ;;
  network) echo '$SKOPEO_ERR_NETWORK' >&2; exit 1 ;;
  bare) exit 1 ;;
esac
EOF

  chmod +x "$MOCK_BIN_DIR/skopeo"
}


# Cleanup mock functions and directories
cleanup_mocks() {
  # Unset mock functions
  unset -f oc 2>/dev/null || true

  # Unset mock environment variables
  unset MOCK_SNAPSHOT_NAME MOCK_BUNDLE_IMAGE MOCK_BUNDLE_VERSION 2>/dev/null || true

  # Remove mock binary directory and restore PATH
  if [ -n "${MOCK_BIN_DIR:-}" ] && [ -d "$MOCK_BIN_DIR" ]; then
    # Remove from start of PATH (where setup_mock_bin_dir added it)
    export PATH="${PATH#${MOCK_BIN_DIR}:}"
    rm -rf "$MOCK_BIN_DIR"
  fi

  # Unset the MOCK_BIN_DIR variable
  unset MOCK_BIN_DIR 2>/dev/null || true
}
