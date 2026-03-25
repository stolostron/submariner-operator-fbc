#!/bin/bash
set -euo pipefail

if [[ $(basename "${PWD}") != "submariner-operator-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

OPM_IMAGE="quay.io/operator-framework/opm:latest"

#------------------------------------------------------------------------------
# retry_command - Retry command up to 3 times with exponential backoff
#
# Handles transient registry 503 errors that podman/skopeo retry but opm doesn't
#------------------------------------------------------------------------------
retry_command() {
    local max_attempts=3
    local timeout=2
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        set +e
        "$@"
        exitCode=$?
        set -e

        if [ $exitCode -eq 0 ]; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "    --> Attempt $attempt/$max_attempts failed (exit $exitCode). Retrying in ${timeout}s..."
            sleep $timeout
            timeout=$((timeout * 2))
        fi
        attempt=$((attempt + 1))
    done

    echo "    --> ERROR: Command failed after $max_attempts attempts"
    return $exitCode
}

# Render older catalogs (OCP <= 4.16)
echo "--> Rendering catalogs for OCP <= 4.16..."
echo "    (These versions do not require any special rendering flags.)"
old_catalog_templates=$(find . -name "catalog-template-*.yaml" | grep -e "4-14" -e "4-15" -e "4-16")

for catalog_template in ${old_catalog_templates}; do
  output_catalog="${catalog_template//-template/}"
  echo "    --> Rendering ${catalog_template} to ${output_catalog}..."

  # Check if the template contains registry.redhat.io URLs, which require auth.
  # If found, use local opm with authentication. Container opm does not reliably
  # handle registry.redhat.io authentication in all environments.
  # NOTE: Local opm may fail in some environments with DNS errors like:
  # `dial tcp: lookup quay.io on [::1]:53: read: connection refused`.
  # In such cases, podman with quay.io URLs works reliably.
  if grep -q "registry.redhat.io" "${catalog_template}"; then
    echo "    --> Found registry.redhat.io URL, using local opm with auth..."
    DOCKER_CONFIG=~/.docker/ retry_command ./bin/opm alpha render-template basic "${catalog_template}" -o=yaml > "${output_catalog}"
  else
    echo "    --> No private registries detected, using podman..."
    podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
      alpha render-template basic "${catalog_template}" \
      -o=yaml > "${output_catalog}"
  fi

  echo "    --> Rendering complete for ${output_catalog}"
done

# Render newer catalogs (OCP >= 4.17)
echo ""
echo "--> Rendering catalogs for OCP >= 4.17..."
echo "    (These versions require the --migrate-level=bundle-object-to-csv-metadata flag for compatibility.)"
new_catalog_templates=$(find . -name "catalog-template-*.yaml" | grep -v -e "4-14" -e "4-15" -e "4-16")

for catalog_template in ${new_catalog_templates}; do
  output_catalog="${catalog_template//-template/}"
  echo "    --> Rendering ${catalog_template} to ${output_catalog}..."

  # Same authentication logic as older OCP versions (see comment above)
  if grep -q "registry.redhat.io" "${catalog_template}"; then
    echo "    --> Found registry.redhat.io URL, using local opm with auth..."
    DOCKER_CONFIG=~/.docker/ retry_command ./bin/opm alpha render-template basic "${catalog_template}" -o=yaml --migrate-level=bundle-object-to-csv-metadata > "${output_catalog}"
  else
    echo "    --> No private registries detected, using podman..."
    podman run --rm -v "$(pwd)":/work:z -v /etc/containers:/etc/containers:ro -w /work "${OPM_IMAGE}" \
      alpha render-template basic "${catalog_template}" \
      -o=yaml --migrate-level=bundle-object-to-csv-metadata > "${output_catalog}"
  fi

  echo "    --> Rendering complete for ${output_catalog}"
done

echo "--> All rendering complete."

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
