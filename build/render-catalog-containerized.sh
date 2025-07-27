#!/bin/bash
set -ex

OPM_IMAGE="quay.io/operator-framework/opm:latest"
CATALOG_TEMPLATE="catalog-template-4-17.yaml"
OUTPUT_CATALOG="catalog-4-17.yaml"

echo "Rendering ${CATALOG_TEMPLATE} to ${OUTPUT_CATALOG} using a container..."

# This command runs 'opm' in a container to render the catalog template.
# It mounts the current directory to /work in the container, so opm can access the template file.
# It also mounts the host's container policy to ensure images can be pulled.
# The output of the command is redirected to create the final catalog file.
podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
  alpha render-template basic "${CATALOG_TEMPLATE}" \
  -o=yaml --migrate-level=bundle-object-to-csv-metadata > "${OUTPUT_CATALOG}"

echo "Rendering complete. Check the ${OUTPUT_CATALOG} file."

