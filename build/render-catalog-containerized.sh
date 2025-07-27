#!/bin/bash
set -ex

OPM_IMAGE="quay.io/operator-framework/opm:latest"

# Find all catalog templates, excluding older versions
catalog_templates=$(find . -name "catalog-template-*.yaml" | grep -v -e "4-14" -e "4-15" -e "4-16")

for catalog_template in ${catalog_templates}; do
  output_catalog="${catalog_template//-template/}"
  echo "Rendering ${catalog_template} to ${output_catalog} using a container..."

  podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
    alpha render-template basic "${catalog_template}" \
    -o=yaml --migrate-level=bundle-object-to-csv-metadata > "${output_catalog}"

  echo "Rendering complete for ${output_catalog}"
done

echo "All rendering complete."