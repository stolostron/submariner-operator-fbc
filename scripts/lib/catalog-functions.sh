#!/bin/bash
#
# catalog-functions.sh - Pure functions for FBC catalog manipulation
#
# This library provides reusable functions for querying and manipulating
# File-Based Catalog (FBC) templates. All functions are designed to be
# testable with minimal side effects.
#

set -euo pipefail

#------------------------------------------------------------------------------
# SHA Extraction and Validation
#------------------------------------------------------------------------------

# Extract SHA from image URL
# Parameters: $1 = image URL with @sha256:...
# Returns: SHA hex string (without sha256: prefix), or empty if not found
# Note: Validates SHA256 is exactly 64 hex characters
extract_sha() {
  echo "$1" | grep -oP 'sha256:\K[a-f0-9]{64}'
}

#------------------------------------------------------------------------------
# Version Validation
#------------------------------------------------------------------------------

# Validate version format (0.X.Y for Submariner)
# Parameters: $1 = version string
# Returns: 0 if valid, 1 if invalid
validate_version_format() {
  local version="$1"
  [ -z "$version" ] && return 1

  # Validate 0.X.Y format (Submariner major version is always 0)
  [[ "$version" =~ ^0\.([0-9]+)\.([0-9]+)$ ]] || return 1

  local minor="${BASH_REMATCH[1]}"

  # Submariner 0.18+ is minimum supported version
  if [ "$minor" -lt 18 ]; then
    echo "ERROR: Submariner version must be >= 0.18.0 (got: $version)" >&2
    return 1
  fi

  return 0
}

#------------------------------------------------------------------------------
# Bundle Queries
#------------------------------------------------------------------------------

# Get bundle entry from catalog template
# Parameters: $1 = bundle name
# Returns: Full bundle entry YAML, or empty if not found (exit 0)
# Returns: exit 1 only for precondition failures (invalid params/missing file)
get_bundle_entry() {
  local bundle_name="$1"
  [ -z "$bundle_name" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  BUNDLE_NAME="$bundle_name" yq eval '.entries[] | select(.schema == "olm.bundle" and .name == env(BUNDLE_NAME))' catalog-template.yaml
  return 0
}

# Get bundle image from catalog template
# Parameters: $1 = bundle name
# Returns: Image URL with SHA, or empty if not found (exit 0)
# Returns: exit 1 only for precondition failures (invalid params/missing file)
get_bundle_image() {
  local bundle_name="$1"
  [ -z "$bundle_name" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  # Use // "" (yq's alternative operator) to convert null/false to empty string
  BUNDLE_NAME="$bundle_name" yq eval '.entries[] | select(.schema == "olm.bundle" and .name == env(BUNDLE_NAME)) | .image // ""' catalog-template.yaml
  return 0
}

# Check if bundle exists in template
# Parameters: $1 = bundle name
# Returns: 0 if exists, 1 if not
bundle_exists_in_template() {
  local bundle_name="$1"
  [ -z "$bundle_name" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  [ -n "$(get_bundle_entry "$bundle_name")" ]
}

#------------------------------------------------------------------------------
# Channel Queries
#------------------------------------------------------------------------------

# Check if channel exists in catalog template
# Parameters: $1 = channel name
# Returns: 0 if exists, 1 if not
channel_exists() {
  local channel_name="$1"
  [ -z "$channel_name" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  [ -n "$(CHANNEL_NAME="$channel_name" yq eval '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL_NAME))' catalog-template.yaml)" ]
}

# Get number of entries in a channel
# Parameters: $1 = channel name
# Returns: Entry count (0 for empty channel), or empty if channel not found (exit 0)
# Returns: exit 1 only for precondition failures (invalid params/missing file)
get_channel_entry_count() {
  local channel_name="$1"
  [ -z "$channel_name" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  CHANNEL_NAME="$channel_name" yq eval '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL_NAME)) | .entries | length' catalog-template.yaml
  return 0
}

# Get latest (last) entry in a channel
# Parameters: $1 = channel name
# Returns: Latest bundle name, or empty if channel empty/not found (exit 0)
# Returns: exit 1 only for precondition failures (invalid params/missing file)
get_latest_channel_entry() {
  local channel_name="$1"
  [ -z "$channel_name" ] && return 1
  [ -f "catalog-template.yaml" ] || return 1
  # Handle empty channels: return empty string instead of "null"
  # Get entries array, check if length > 0, then get last element, otherwise return empty
  local entries
  entries=$(CHANNEL_NAME="$channel_name" yq eval '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL_NAME)) | .entries' catalog-template.yaml)
  if [ -z "$entries" ] || [ "$entries" = "[]" ] || [ "$entries" = "null" ]; then
    echo ""
  else
    echo "$entries" | yq eval '.[-1].name' -
  fi
  return 0
}
