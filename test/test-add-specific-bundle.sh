#!/bin/bash

set -o pipefail
set -o nounset
set -o errexit

TEST_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT=$(realpath "$TEST_DIR/..")

# Test case: Add a specific bundle to the catalog template
test_add_specific_bundle() {
    # Ensure a clean environment before running the test
    "$PROJECT_ROOT/scripts/reset-test-environment.sh"

    BUNDLE_IMAGE=${1:-quay.io/redhat-user-workloads/submariner-tenant/submariner-bundle-0-21@sha256:bad7ce0c4a3edcb12dc3adf3e4165bd57631c06bc81ed9b507377b12e73f905c}

    echo "Attempting to add bundle '$BUNDLE_IMAGE' to the catalog template..."
    "$PROJECT_ROOT/build/add-bundle.sh" "$BUNDLE_IMAGE"

    # Re-extract metadata for verification purposes
    BUNDLE_METADATA=$("$PROJECT_ROOT/scripts/get-bundle-metadata.sh" "$BUNDLE_IMAGE")
    BUNDLE_VERSION=$(echo "$BUNDLE_METADATA" | grep "^BUNDLE_VERSION=" | cut -d'=' -f2)
    BUNDLE_CHANNELS=$(echo "$BUNDLE_METADATA" | grep "^BUNDLE_CHANNELS=" | cut -d'=' -f2)

    # Verify that the bundle is added to the catalog-template.yaml
    if ! yq e '.spec.bundles[] | select(.image == "'"$BUNDLE_IMAGE"'")' "$PROJECT_ROOT/catalog-template.yaml" > /dev/null; then
        echo "Error: Bundle '$BUNDLE_IMAGE' was NOT found in catalog-template.yaml. Test failed."
        exit 1
    fi

    if ! yq e '.spec.bundles[] | select(.image == "'"$BUNDLE_IMAGE"'") | .version == "'"$BUNDLE_VERSION"'"' "$PROJECT_ROOT/catalog-template.yaml" > /dev/null; then
        echo "Error: Bundle '$BUNDLE_IMAGE' version mismatch. Expected '$BUNDLE_VERSION', but found something else. Test failed."
        exit 1
    fi

    echo "Verification: Bundle '$BUNDLE_IMAGE' successfully found in catalog-template.yaml."

    # Verify that the bundle is added to the correct channels
    for channel in ${BUNDLE_CHANNELS//,/ }; do
        echo "Verifying bundle 'submariner.$BUNDLE_VERSION' presence in channel '$channel'..."
        if ! yq e '.entries[] | select(.schema == "olm.channel") | select(.name == "'"$channel"'").entries[] | select(.name == "submariner.'"$BUNDLE_VERSION"'")' "$PROJECT_ROOT/catalog-template.yaml" > /dev/null; then
            echo "Error: Bundle 'submariner.$BUNDLE_VERSION' was NOT found in channel '$channel'. Test failed."
            exit 1
        fi
        echo "Verification: Bundle 'submariner.$BUNDLE_VERSION' successfully found in channel '$channel'."
    done

}

# Run the test
test_add_specific_bundle
