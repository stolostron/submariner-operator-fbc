#!/bin/bash
set -ex

OPM_IMAGE="quay.io/operator-framework/opm:latest"

# Render older catalogs (OCP <= 4.16)
echo "Rendering catalogs for OCP <= 4.16..."
old_catalog_templates=$(find . -name "catalog-template-*.yaml" | grep -e "4-14" -e "4-15" -e "4-16")

for catalog_template in ${old_catalog_templates}; do
  output_catalog="${catalog_template//-template/}"
  echo "Rendering ${catalog_template} to ${output_catalog} using a container..."

  podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
    alpha render-template basic "${catalog_template}" \
    -o=yaml > "${output_catalog}"

  echo "Rendering complete for ${output_catalog}"
done

# Render newer catalogs (OCP >= 4.17)
echo ""
echo "Rendering catalogs for OCP >= 4.17..."
new_catalog_templates=$(find . -name "catalog-template-*.yaml" | grep -v -e "4-14" -e "4-15" -e "4-16")

for catalog_template in ${new_catalog_templates}; do
  output_catalog="${catalog_template//-template/}"
  echo "Rendering ${catalog_template} to ${output_catalog} using a container..."

  podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
    alpha render-template basic "${catalog_template}" \
    -o=yaml --migrate-level=bundle-object-to-csv-metadata > "${output_catalog}"

  echo "Rendering complete for ${output_catalog}"
done

echo "All rendering complete."

# Decompose the catalog into files for consumability
echo ""
echo "Decomposing catalogs into file-based catalogs..."
catalogs=$(find . -name "catalog-*.yaml" -not -name "catalog-template*.yaml")
rm -rf catalog-/

for catalog_file in ${catalogs}; do
  catalog_dir=${catalog_file%\.yaml}
  mkdir -p "${catalog_dir}"/{bundles,channels}

  echo "Decomposing ${catalog_file} into directory for consumability: ${catalog_dir}/ ..."

  yq eval-all -s "select(.schema == \"olm.bundle\") | \"${catalog_dir}/bundles/bundle-v\" + (.properties[] | select(.type == \"olm.package\").value.version) + \".yaml\"" "${catalog_file}"
  yq eval-all -s "select(.schema == \"olm.channel\") | \"${catalog_dir}/channels/channel-\" + .name + \".yaml\"" "${catalog_file}"
  yq eval 'select(.schema == "olm.package")' "${catalog_file}" > "${catalog_dir}/package.yaml"

  # Rename the files to remove the extra .yml extension
  for f in ${catalog_dir}/bundles/*.yml ${catalog_dir}/channels/*.yml; do
    mv -- "$f" "${f%.yml}"
  done

  rm "${catalog_file}"
done

echo "Decomposition complete."