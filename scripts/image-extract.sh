#!/bin/bash

# Exit immediately if a command fails
set -e

if [[ "${SKIP_AUTH_TESTS:-false}" = "true" ]]; then
  echo "Skipping image-extract.sh as SKIP_AUTH_TESTS is set to true."
  exit 0
fi

# --- Configuration ---
# The base directory where subdirectories for images will be created.
BASE_DIR="."

# If a second argument is provided, use it as the base directory
if [ -n "$2" ]; then
  BASE_DIR="$2"
fi

# Change to the base directory to ensure all operations are relative to it
cd "$BASE_DIR"

# --- Script Logic ---

# Check if an image ID/name was provided as an argument
if [ -z "$1" ]; then
  echo "❌ Error: No image specified."
  echo "Usage: ./image-extract.sh <image_name:tag | image_id>"
  exit 1
fi

IMAGE_ID="$1"
# Sanitize the image ID to create a valid directory name.
# Replaces characters that are not alphanumeric, dot, underscore, or hyphen with an underscore.
DIR_NAME=$(echo "$IMAGE_ID" | sed -e 's/[^a-zA-Z0-9._-]/_/g')
OUTPUT_DIR="$BASE_DIR/$DIR_NAME"

echo "➡️  Extracting files from image '$IMAGE_ID'..."

# Create the output directory, ensuring it's clean
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "    Creating temporary container..."
# Create a temporary container from the image. We just need its filesystem.
CONTAINER_ID=$(podman create "$IMAGE_ID")

# Ensure the temporary container is removed when the script exits, even on error
trap 'echo "    Cleaning up temporary container..."; podman rm "$CONTAINER_ID" >/dev/null' EXIT

echo "    Exporting and extracting filesystem to '$OUTPUT_DIR'..."
# Export the container's filesystem as a tar stream and pipe it to tar to extract
podman export "$CONTAINER_ID" | tar --no-same-owner -C "$OUTPUT_DIR" -xf -

# Set appropriate permissions for the extracted files
chmod -R u+rwX,go+rX,go-w "$OUTPUT_DIR"



echo "✅ Extraction complete!"
