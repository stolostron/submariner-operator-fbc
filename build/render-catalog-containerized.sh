#!/bin/bash
set -ex

if [[ $(basename "${PWD}") != "submariner-operator-product-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

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

  # Extract and write the olm.bundle
  bundle_content=$(yq eval 'select(.schema == "olm.bundle")' "${catalog_file}")
  if [ -n "$bundle_content" ]; then
    bundle_version=$(echo "${bundle_content}" | yq eval '.properties[] | select(.type == "olm.package").value.version' -)
    bundle_file="${catalog_dir}/bundles/bundle-v${bundle_version}.yaml"
    echo "${bundle_content}" > "${bundle_file}"
    echo "  - Wrote bundle to ${bundle_file}"
  fi

  # Extract and write the olm.channel
  channel_content=$(yq eval 'select(.schema == "olm.channel")' "${catalog_file}")
  if [ -n "$channel_content" ]; then
    channel_name=$(echo "${channel_content}" | yq eval '.name' -)
    channel_file="${catalog_dir}/channels/channel-${channel_name}.yaml"
    echo "---" > "${channel_file}"
    echo "${channel_content}" >> "${channel_file}"
    echo "  - Wrote channel to ${channel_file}"
  fi

  # Extract and write the olm.package
  package_content=$(yq eval 'select(.schema == "olm.package")' "${catalog_file}")
  if [ -n "$package_content" ]; then
    package_file="${catalog_dir}/package.yaml"
    echo "${package_content}" > "${package_file}"
    echo "  - Wrote package to ${package_file}"
  fi

  rm "${catalog_file}"
done

# Use oldest catalog to populate bundle names for reference
oldest_catalog=$(find catalog-* -type d | head -1)

for bundle in "${oldest_catalog}"/bundles/*.yaml; do
  bundle_image=$(yq '.image' "${bundle}")
  bundle_name=$(yq '.name' "${bundle}")

  yq '.entries[] |= select(.image == "'"${bundle_image}"'").name = "'"${bundle_name}"'"' -i catalog-template.yaml
done

echo "Decomposition complete."
