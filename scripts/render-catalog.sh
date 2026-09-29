#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
OPM_IMAGE="${OPM_IMAGE:-quay.io/operator-framework/opm:v1.56.0}"

# Buffer each attempt: neither partial YAML nor retry diagnostics reach stdout.
retry_command() {
  local attempt output rc=1
  output=$(mktemp)
  for attempt in 1 2 3; do
    if "$@" > "$output"; then
      cat "$output"
      rm -f "$output"
      return 0
    else rc=$?; fi
    echo "Render attempt $attempt failed (exit $rc)" >&2
    [ "$attempt" -eq 3 ] || sleep "$attempt"
  done
  rm -f "$output"
  return "$rc"
}

shopt -s nullglob
catalog_templates=(catalog-template-*-*.yaml)
[ "${#catalog_templates[@]}" -gt 0 ] || { echo "No catalog templates" >&2; exit 1; }
for catalog_template in "${catalog_templates[@]}"; do
  output_catalog="${catalog_template//-template/}"
  flags=()
  case "$catalog_template" in
    catalog-template-4-14.yaml|catalog-template-4-15.yaml|catalog-template-4-16.yaml) ;;
    *) flags+=(--migrate-level=bundle-object-to-csv-metadata) ;;
  esac
  if grep -q "registry.redhat.io" "$catalog_template"; then
    DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}" retry_command ./bin/opm alpha render-template basic "$catalog_template" -o=yaml "${flags[@]}" > "$output_catalog.tmp"
  else
    retry_command podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "$OPM_IMAGE" \
      alpha render-template basic "$catalog_template" -o=yaml "${flags[@]}" > "$output_catalog.tmp"
  fi
  mv "$output_catalog.tmp" "$output_catalog"
done

# Decompose the catalog into files for consumability
echo ""
echo "--> Decomposing rendered catalogs into file-based catalogs..."
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
    if [ ! -s "${doc_file}" ]; then
      rm "${doc_file}"
      continue
    fi

    schema=$(yq eval '.schema' "${doc_file}")

    if [[ "${schema}" == "olm.bundle" ]]; then
      bundle_version=$(yq eval '.properties[] | select(.type == "olm.package").value.version' "${doc_file}")
      bundle_release=$(yq eval '.properties[] | select(.type == "olm.package").value.release' "${doc_file}")
      if [[ "${bundle_release}" != "null" && -n "${bundle_release}" ]]; then
        bundle_version="${bundle_version}+${bundle_release}"
      fi
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

echo "--> Sorting the main catalog-template.yaml file..."
# Ensure consistent ordering: package first, then channels (alphabetical), then bundles (alphabetical)
yq '.entries |=
    [(.[] | select(.schema == "olm.package"))] +
   ([(.[] | select(.schema == "olm.channel"))] | sort_by(.name)) +
   ([(.[] | select(.schema == "olm.bundle"))] | sort_by(.name))' -i catalog-template.yaml

echo "--> Replacing development image URLs with production URLs..."
# Use nullglob to handle case where no bundles exist
shopt -s nullglob
bundle_files=(catalog-*/bundles/*.yaml)
shopt -u nullglob

if [ ${#bundle_files[@]} -eq 0 ]; then
  echo "    --> No bundle files found, skipping URL replacement"
else
  for file in "${bundle_files[@]}"; do
    sed -i -E 's%quay.io/redhat-user-workloads/[^:@]+%registry.redhat.io/rhacm2/submariner-operator-bundle%g' "${file}"
  done
  echo "    --> Replaced URLs in ${#bundle_files[@]} bundle files"
fi
