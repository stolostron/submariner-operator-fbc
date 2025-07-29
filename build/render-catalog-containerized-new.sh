#! /bin/bash

set -ex

OPM_IMAGE="quay.io/operator-framework/opm:latest"

if [[ $(basename "${PWD}") != "submariner-operator-product-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

# Render the template to a catalog

##### Special case for OCP <=4.16 #####
echo "Rendering catalogs with olm.bundle.object for OCP <=4.16 ..."
old_catalog_templates=$(find catalog-template-*.yaml | grep -e "4-14" -e "4-15" -e "4-16")
for old_catalog_template in ${old_catalog_templates}; do
  echo "  Rendering catalog with ${old_catalog_template} ..."
  podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
    alpha render-template basic "${old_catalog_template}" -o=yaml > "${old_catalog_template//-template/}"
done
#######################################

echo ""

#catalog_templates=$(find catalog-template-*.yaml -not -name "catalog-template-4-14.yaml")
catalog_templates=$(find catalog-template-*.yaml | grep -v -e "4-14" -e "4-15" -e "4-16")

echo "Rendering catalogs with olm.csv.meatadata for OCP >=4.17 ..."
for catalog_template in ${catalog_templates}; do
  echo "  Rendering catalog with ${catalog_template} ..."

  podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
    alpha render-template basic "${catalog_template}" -o=yaml --migrate-level=bundle-object-to-csv-metadata > "${catalog_template//-template/}"
done

# Decompose the catalog into files for consumability
catalogs=$(find catalog-*.yaml -not -name "catalog-template*.yaml")
rm -rf catalog-*/

for catalog_file in ${catalogs}; do
  catalog_dir=${catalog_file%\.yaml}
  echo "Decomposing ${catalog_file} into directory for consumability: ${catalog_dir}/ ..."
  yq 'select(.schema == "olm.bundle")' -s '"'"${catalog_dir}"'/bundles/bundle-v" + (.properties[] | select(.type == "olm.package").value.version) + ".yaml"' "${catalog_file}"
  yq 'select(.schema == "olm.channel")' -s '"'"${catalog_dir}"'/channels/channel-" + (.name) + ".yaml"' "${catalog_file}"
  yq 'select(.schema == "olm.package")' -s '"'"${catalog_dir}"'/package.yaml"' "${catalog_file}"
  rm "${catalog_file}"
done

rm catalog-template-*.yaml

# Use oldest catalog to populate bundle names for reference
oldest_catalog=$(find catalog-* -type d | head -1)

for bundle in "${oldest_catalog}"/bundles/*.yaml; do
  bundle_image=$(yq '.image' "${bundle}")
  bundle_name=$(yq '.name' "${bundle}")

  yq '.entries[] |= select(.image == "'"${bundle_image}"'").name = "'"${bundle_name}"'"' -i catalog-template.yaml
done

# Sort catalog
yq '.entries |= (sort_by(.schema, .name) | reverse)' -i catalog-template.yaml
yq '.entries |=
    [(.[] | select(.schema == "olm.package"))] +
   ([(.[] | select(.schema == "olm.channel"))] | sort_by(.name)) +
   ([(.[] | select(.schema == "olm.bundle"))] | sort_by(.name))' -i catalog-template.yaml

# Fix sed issues on mac by using GSED
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
SED="sed"
if [ "${OS}" == "darwin" ]; then
  SED="gsed"
fi

# Replace the Konflux images with production images
for file in catalog-template.yaml catalog-*/bundles/*.yaml; do
  ${SED} -i -E 's%quay.io/redhat-user-workloads/[^@]+%registry.redhat.io/rhacm2/submariner-operator-bundle%g' "${file}"
done
