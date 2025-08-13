#! /bin/bash

set -e

if [[ $(basename "${PWD}") != "submariner-operator-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

echo "This script generates a set of catalog templates, one for each supported OCP version."
echo "The templates are generated from the base catalog-template.yaml file, and then pruned"
echo "based on the versions defined in drop-versions.json."
echo
echo "Using drop version Submariner map:"
echo "    (Keys are OCP versions, values are the minimum Submariner version to include for that OCP version.)"
jq '.' drop-versions.json

ocp_versions=$(jq -r 'keys[]' drop-versions.json)

shouldPrune() {
  oldest_version="$(jq -r ".[\"${1}\"]" drop-versions.json).99"

  [[ "$(printf "%s\n%s\n" "${2}" "${oldest_version}" | sort --version-sort | tail -1)" == "${oldest_version}" ]]

  return $?
}

for version in ${ocp_versions}; do
  cp catalog-template.yaml "catalog-template-${version//./-}.yaml"
  # OPM does not like comments, will fail with a JSON parsing error, so remove them
  grep -v '^#' "catalog-template-${version//./-}.yaml" > "catalog-template-${version//./-}.yaml.tmp"
  mv "catalog-template-${version//./-}.yaml.tmp" "catalog-template-${version//./-}.yaml"
done

for ocp_version in ${ocp_versions}; do
  echo "# Pruning catalog for OCP ${ocp_version}..."

  # Prune channels
  for channel in $(yq -r '.entries[] | select(.schema == "olm.channel").name' "catalog-template-${ocp_version//./-}.yaml"); do
    if shouldPrune "${ocp_version}" "${channel#*\-}"; then
      echo "  - Pruning channel: ${channel}"
      yq -i '.entries |= del(.[] | select(.schema == "olm.channel" and .name == "'"${channel}"'"))' "catalog-template-${ocp_version//./-}.yaml"
    fi
  done

  # Prune bundles from channels
  for channel in $(yq -r '.entries[] | select(.schema == "olm.channel").name' "catalog-template-${ocp_version//./-}.yaml"); do
    for entry in $(yq -r '.entries[] | select(.schema == "olm.channel" and .name == "'"${channel}"'").entries[].name' "catalog-template-${ocp_version//./-}.yaml"); do
      version=${entry#*\.v}
      if shouldPrune "${ocp_version}" "${version}"; then
        echo "  - Pruning entry from channel ${channel}: ${entry}"
        yq -i '.entries[] |= (select(.schema == "olm.channel" and .name == "'"${channel}"'").entries |= del(.[] | select(.name == "'"${entry}"'")))' "catalog-template-${ocp_version//./-}.yaml"
      fi
    done
  done

  # Get all referenced bundle images
  referenced_bundle_images=$(yq -r '.entries[] | select(.schema == "olm.channel") | .entries[].name' "catalog-template-${ocp_version//./-}.yaml" | sort -u)

  # Prune unreferenced bundles
  for bundle_image in $(yq -r '.entries[] | select(.schema == "olm.bundle").image' "catalog-template-${ocp_version//./-}.yaml"); do
    bundle_name_in_template=$(yq -r '.entries[] | select(.schema == "olm.bundle" and .image == "'"${bundle_image}"'").name' "catalog-template-${ocp_version//./-}.yaml")
    if ! echo "${referenced_bundle_images}" | grep -q "${bundle_name_in_template}"; then
      echo "  - Pruning unreferenced bundle: ${bundle_name_in_template}"
      yq -i '.entries |= del(.[] | select(.schema == "olm.bundle" and .image == "'"${bundle_image}"'"))' "catalog-template-${ocp_version//./-}.yaml"
    fi
  done

  # Handle replaces field
  for channel in $(yq -r '.entries[] | select(.schema == "olm.channel").name' "catalog-template-${ocp_version//./-}.yaml"); do
    channel_entries=$(yq -r '.entries[] | select(.schema == "olm.channel" and .name == "'"${channel}"'").entries | length' "catalog-template-${ocp_version//./-}.yaml")
    if [[ "${channel_entries}" == "1" ]]; then
      echo "  - Channel ${channel} has only one bundle, removing the 'replaces' field."
      yq -i '.entries[] |= (select(.schema == "olm.channel" and .name == "'"${channel}"'").entries[0] |= del(.replaces))' "catalog-template-${ocp_version//./-}.yaml"
    fi
  done
done
