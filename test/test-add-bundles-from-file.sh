#!/bin/bash

set -euo pipefail

./scripts/reset-test-environment.sh

# Settings
# The yaml file to read bundle images from
BUNDLE_IMAGES_FILE="${1:-test/test-bundle-images.yaml}"

# Check if the bundle images file exists
if [ ! -f "${BUNDLE_IMAGES_FILE}" ]; then
    echo "Error: Bundle images file not found at ${BUNDLE_IMAGES_FILE}"
    exit 1
fi

# Read the bundle image URLs from the yaml file and add them
yq -r '.bundle_image_urls[]' "${BUNDLE_IMAGES_FILE}" | while read -r bundle_image; do
    echo "Adding bundle: ${bundle_image}"
    if ! ./build/add-bundle.sh "${bundle_image}"; then
        echo "Error: Failed to add bundle ${bundle_image}"
        exit 1
    fi
done

# Build the catalogs
echo "Building catalogs..."
if ! ./build/build.sh; then
    echo "Error: Failed to build catalogs"
    exit 1
fi

# Verify the bundles were added correctly
yq -r '.bundle_image_urls[]' "${BUNDLE_IMAGES_FILE}" | while read -r bundle_image; do
    # Get bundle metadata
    # shellcheck source=/dev/null
    source <(./scripts/get-bundle-metadata.sh "${bundle_image}")

    # Check that the bundle was added to the correct catalogs
    for channel in ${BUNDLE_CHANNELS//,/ }; do
        for catalog in catalog-4-*; do
            if [[ -f "${catalog}/package.yaml" ]]; then
                echo "Verifying bundle in ${catalog} for channel ${channel}..."
                if ! yq -e ".entries[] | select(.name == \"submariner.${BUNDLE_VERSION}\")" "${catalog}/channels/channel-${channel}.yaml" > /dev/null; then
                    echo "Error: Bundle not found in ${catalog} for channel ${channel}"
                    exit 1
                fi

                # Check that the bundle file was created and contains the correct image URL
                bundle_file=$(grep -l "${BUNDLE_DIGEST}" "${catalog}/bundles/"*.yaml || true)
                if [[ -f "${bundle_file}" ]]; then
                    echo "Verifying bundle file ${bundle_file}..."
                else
                    echo "Error: Bundle file with digest ${BUNDLE_DIGEST} not found in ${catalog}/bundles/"
                    exit 1
                fi
            fi
        done
    done
done

echo "Successfully added all bundles and built catalogs."
