#!/bin/bash
#
# test-constants.sh - Shared test data constants
#
# Centralizes version numbers, SHAs, URLs, and other test data to eliminate
# duplication across test files.

#------------------------------------------------------------------------------
# Version Constants
#------------------------------------------------------------------------------

# Commonly used versions in tests
export TEST_VERSION_21_0="0.21.0"
export TEST_VERSION_21_2="0.21.2"
export TEST_VERSION_21_3="0.21.3"
export TEST_VERSION_22_0="0.22.0"
export TEST_VERSION_22_1="0.22.1"
export TEST_VERSION_23_1="0.23.1"
export TEST_VERSION_24_0="0.24.0"

# Version patterns (Y-stream notation)
export TEST_Y_STREAM_21="0-21"
export TEST_Y_STREAM_22="0-22"
export TEST_Y_STREAM_23="0-23"
export TEST_Y_STREAM_24="0-24"

# Version boundaries and edge cases
export TEST_MIN_VERSION="0.18.0"                    # Minimum supported version
export TEST_VERSION_TOO_OLD="0.17.6"                # Below minimum (for rejection tests)
export TEST_VERSION_NONEXISTENT="0.99.0"            # Non-existent version (for not-found tests)
export TEST_VERSION_NONEXISTENT_PATCH="0.99.9"      # Non-existent version with patch
export TEST_CHANNEL_NONEXISTENT="stable-0.99"       # Non-existent channel
export TEST_BUNDLE_NAME_NONEXISTENT="submariner.v0.99.0"  # Non-existent bundle

#------------------------------------------------------------------------------
# SHA Digest Constants
#------------------------------------------------------------------------------

# Test SHAs used in unit tests
export TEST_SHA_ABC123="abc123def4567890abc123def4567890abc123def4567890abc123def4567890"
export TEST_SHA_DEF456="def456abc1234567def456abc1234567def456abc1234567def456abc1234567"
export TEST_SHA_111222="1112223334445556667778889990000aaabbbcccdddeeefff000111222333444"
export TEST_SHA_FEDCBA="fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"

# Real SHAs from catalog-template.yaml (verified against actual bundles)
export TEST_SHA_REAL_21_0="e533406d832461cd8889f5e95569ea9f8dbbd57b51dcd08b56050ba1e3775ad0"  # v0.21.0
export TEST_SHA_REAL="bee92e4e7d305ab6f48d4a06fa7130f59ceebd004bbe802cd41a1eb4ffb98aee"      # v0.21.2

#------------------------------------------------------------------------------
# Snapshot Name Constants
#------------------------------------------------------------------------------

export TEST_SNAPSHOT_21_ABC123="submariner-0-21-abc123"
export TEST_SNAPSHOT_21_DEF456="submariner-0-21-def456"
export TEST_SNAPSHOT_24_XYZ789="submariner-0-24-xyz789"

#------------------------------------------------------------------------------
# Predefined Bundle URLs (commonly used combinations)
#------------------------------------------------------------------------------

export TEST_BUNDLE_QUAY_21_ABC123="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-${TEST_Y_STREAM_21}@sha256:${TEST_SHA_ABC123}"
export TEST_BUNDLE_QUAY_21_DEF456="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-${TEST_Y_STREAM_21}@sha256:${TEST_SHA_DEF456}"
export TEST_BUNDLE_QUAY_22_ABC123="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-${TEST_Y_STREAM_22}@sha256:${TEST_SHA_ABC123}"
export TEST_BUNDLE_QUAY_22_DEF456="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-${TEST_Y_STREAM_22}@sha256:${TEST_SHA_DEF456}"
export TEST_BUNDLE_QUAY_23_DEF456="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-${TEST_Y_STREAM_23}@sha256:${TEST_SHA_DEF456}"
export TEST_BUNDLE_QUAY_24_FEDCBA="quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-${TEST_Y_STREAM_24}@sha256:${TEST_SHA_FEDCBA}"

export TEST_BUNDLE_REGISTRY_ABC123="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${TEST_SHA_ABC123}"
export TEST_BUNDLE_REGISTRY_DEF456="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${TEST_SHA_DEF456}"
export TEST_BUNDLE_REGISTRY_REAL="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${TEST_SHA_REAL}"
export TEST_BUNDLE_REGISTRY_REAL_21_0="registry.redhat.io/rhacm2/submariner-operator-bundle@sha256:${TEST_SHA_REAL_21_0}"

#------------------------------------------------------------------------------
# Bundle Name Constants
#------------------------------------------------------------------------------

export TEST_BUNDLE_NAME_21_0="submariner.v${TEST_VERSION_21_0}"
export TEST_BUNDLE_NAME_21_2="submariner.v${TEST_VERSION_21_2}"
export TEST_BUNDLE_NAME_21_3="submariner.v${TEST_VERSION_21_3}"
export TEST_BUNDLE_NAME_22_0="submariner.v${TEST_VERSION_22_0}"
export TEST_BUNDLE_NAME_22_1="submariner.v${TEST_VERSION_22_1}"
export TEST_BUNDLE_NAME_23_1="submariner.v${TEST_VERSION_23_1}"
export TEST_BUNDLE_NAME_24_0="submariner.v${TEST_VERSION_24_0}"

#------------------------------------------------------------------------------
# Channel Name Constants
#------------------------------------------------------------------------------

export TEST_CHANNEL_21="stable-0.21"
export TEST_CHANNEL_22="stable-0.22"
export TEST_CHANNEL_23="stable-0.23"
export TEST_CHANNEL_24="stable-0.24"

#------------------------------------------------------------------------------
# SkipRange Constants
#------------------------------------------------------------------------------

export TEST_SKIPRANGE_18_21_0=">=0.18.0 <0.21.0"
export TEST_SKIPRANGE_18_21_3=">=0.18.0 <0.21.3"
export TEST_SKIPRANGE_18_22_0=">=0.18.0 <0.22.0"
export TEST_SKIPRANGE_18_24_0=">=0.18.0 <0.24.0"
export TEST_SKIPRANGE_20_21_2=">=0.20.0 <0.21.2"
export TEST_SKIPRANGE_20_21_3=">=0.20.0 <0.21.3"

