#!/bin/bash

set -euo pipefail

# Ensure the script is run from the base of the repository.
if [[ $(basename "${PWD}") != "submariner-operator-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

OUTPUT_DIR="extracted-catalogs"
PACKAGE_NAME="submariner"

# Clean up previous extractions and create the output directory.
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Loop through OCP versions from 4.16 to 4.19
for i in {16..19}; do
  ocp_version="4.${i}"
  echo "--> Fetching and extracting catalog for OCP ${ocp_version}..."

  # Call the existing script to fetch and convert the catalog
  ./scripts/fetch-catalog-containerized.sh "${ocp_version}" "${PACKAGE_NAME}"

  # The output file from the script
  output_yaml="${PACKAGE_NAME}-catalog-config-${ocp_version}.yaml"

  # Move the generated YAML to the output directory
  if [ -f "${output_yaml}" ]; then
    mv "${output_yaml}" "${OUTPUT_DIR}/"
    echo "    Moved ${output_yaml} to ${OUTPUT_DIR}/"
  else
    echo "    Warning: ${output_yaml} not found."
  fi
done

echo "--> All catalogs have been extracted to the ${OUTPUT_DIR} directory."
