#!/bin/bash

set -e

if ! command -v yq &> /dev/null; then
    echo "yq could not be found, please install it."
    echo "See: https://github.com/mikefarah/yq#install"
    exit 1
fi

echo "Running yq -i '.' on all YAML files to standardize formatting..."

# Find all YAML files and apply yq -i '.'
find . -type f \( -name "*.yaml" -o -name "*.yml" \) -not -path "./.tekton/*" -print0 | while IFS= read -r -d $'\0' file; do
  # The config file is intentionally not well-formed yaml, so we skip it
  if [[ "$file" == *"/submariner-catalog-config-4.19.yaml" ]]; then
    echo "Skipping $file..."
    continue
  fi
  echo "Processing $file..."
  yq -i '.' "$file"
done

echo "YAML formatting complete."
