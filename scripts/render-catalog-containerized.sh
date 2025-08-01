#!/bin/bash
set -e

if [[ $(basename "${PWD}") != "submariner-operator-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

OPM_IMAGE="quay.io/operator-framework/opm:latest"

# Render older catalogs (OCP <= 4.16)
echo "--> Rendering catalogs for OCP <= 4.16..."
echo "    (These versions do not require any special rendering flags.)"
old_catalog_templates=$(find . -name "catalog-template-*.yaml" | grep -e "4-14" -e "4-15" -e "4-16")

for catalog_template in ${old_catalog_templates}; do
  output_catalog="${catalog_template//-template/}"
  echo "    --> Rendering ${catalog_template} to ${output_catalog} using the opm container..."

  podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
    alpha render-template basic "${catalog_template}" \
    -o=yaml > "${output_catalog}"

  echo "    --> Rendering complete for ${output_catalog}"
done

# Render newer catalogs (OCP >= 4.17)
echo ""
echo "--> Rendering catalogs for OCP >= 4.17..."
echo "    (These versions require the --migrate-level=bundle-object-to-csv-metadata flag for compatibility.)"
new_catalog_templates=$(find . -name "catalog-template-*.yaml" | grep -v -e "4-14" -e "4-15" -e "4-16")

for catalog_template in ${new_catalog_templates}; do
  output_catalog="${catalog_template//-template/}"
  echo "    --> Rendering ${catalog_template} to ${output_catalog} using the opm container..."

  podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
    alpha render-template basic "${catalog_template}" \
    -o=yaml --migrate-level=bundle-object-to-csv-metadata > "${output_catalog}"

  echo "    --> Rendering complete for ${output_catalog}"
done

echo "--> All rendering complete."

# Decompose the catalog into files for consumability
echo ""
echo "--> Decomposing rendered catalogs into file-based catalogs..."
echo "    (Breaking down the single rendered catalog file into the standard file-based catalog format.)"
catalogs=$(find . -name "catalog-*.yaml" -not -name "catalog-template*.yaml")
rm -rf catalog-/

for catalog_file in ${catalogs}; do
  catalog_dir=${catalog_file%\.yaml}
  mkdir -p "${catalog_dir}"/{bundles,channels}

  echo "    --> Decomposing ${catalog_file} into directory: ${catalog_dir}/ ..."

  # Split the multi-document YAML file into individual files
  csplit -s -f "${catalog_dir}/doc" "${catalog_file}" /---/ "{*}"

  for doc_file in "${catalog_dir}"/doc*;
  do
    # if the file is empty, remove it
    if [ ! -s "${doc_file}" ]; then
      rm "${doc_file}"
      continue
    fi

    schema=$(yq eval '.schema' "${doc_file}")

    if [[ "${schema}" == "olm.bundle" ]]; then
      bundle_version=$(yq eval '.properties[] | select(.type == "olm.package").value.version' "${doc_file}")
      bundle_file="${catalog_dir}/bundles/bundle-v${bundle_version}.yaml"
      mv "${doc_file}" "${bundle_file}"
      echo "      - Wrote bundle to ${bundle_file}"
    elif [[ "${schema}" == "olm.channel" ]]; then
      channel_name=$(yq eval '.name' "${doc_file}")
      channel_file="${catalog_dir}/channels/channel-${channel_name}.yaml"
      mv "${doc_file}" "${channel_file}"
      echo "      - Wrote channel to ${channel_file}"
    elif [[ "${schema}" == "olm.package" ]]; then
      package_file="${catalog_dir}/package.yaml"
      mv "${doc_file}" "${package_file}"
      echo "      - Wrote package to ${package_file}"
    else
      rm "${doc_file}"
    fi
  done

  rm "${catalog_file}"
done


echo "--> Decomposition complete."

# Use oldest catalog to populate bundle names for reference
oldest_catalog=$(find catalog-* -type d | head -1)

for bundle in "${oldest_catalog}"/bundles/*.yaml; do
  bundle_image=$(yq '.image' "${bundle}")
  bundle_name=$(yq '.name' "${bundle}")
done

echo "--> Sorting the main catalog-template.yaml file..."
# Sort catalog
yq '.entries |= (sort_by(.schema, .name) | reverse)' -i catalog-template.yaml
yq '.entries |=
    [(.[] | select(.schema == "olm.package"))] +
   ([(.[] | select(.schema == "olm.channel"))] | sort_by(.name)) +
   ([(.[] | select(.schema == "olm.bundle"))] | sort_by(.name))' -i catalog-template.yaml

echo "--> Replacing development image URLs with production URLs..."
# Replace the Konflux images with production images
for file in catalog-*/bundles/*.yaml; do
  sed -i -E 's%quay.io/redhat-user-workloads/[^:@]+%registry.redhat.io/rhacm2/submariner-operator-bundle%g' "${file}"
done