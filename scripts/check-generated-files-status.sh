#!/bin/bash

set -euo pipefail

# This script checks for uncommitted changes in the generated catalog directories
# and the catalog-template.yaml file.

echo "--> Verifying git status of generated files..."

if git status --porcelain catalog-*/ catalog-template.yaml | grep -q .; then
    echo "  [ERROR] Uncommitted changes detected in generated files:"
    git status --porcelain catalog-*/ catalog-template.yaml
    exit 1
fi

echo "  [SUCCESS] Git status of generated files is clean."
