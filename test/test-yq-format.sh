#!/bin/bash

echo "Running yq -i '.' on all YAML files and checking for changes..."

# Find all YAML files and apply yq -i '.'
find . -name "*.yaml" -o -name "*.yml" | while read -r file; do
  echo "Processing $file..."
  yq -i '.' "$file"
done

# Check for changes
if git status --porcelain | grep -qE "^(M|A|D)"; then
  echo "ERROR: yq -i '.' introduced changes to YAML files."
  git status --porcelain
  exit 1
else
  echo "SUCCESS: No changes detected after running yq -i '.' on YAML files."
  exit 0
fi
