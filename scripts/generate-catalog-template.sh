#! /bin/bash

set -e

if [[ $(basename "${PWD}") != "submariner-operator-fbc" ]]; then
  echo "error: Script must be run from the base of the repository."
  exit 1
fi

echo "This script generates OCP-version-specific catalog templates by filtering"
echo "the base catalog-template.yaml to include only Submariner versions that support"
echo "each OCP version (configured in drop-versions.json)."
echo
echo "Using drop version Submariner map:"
jq '.' drop-versions.json

ocp_versions=$(jq -r 'keys[]' drop-versions.json)

is_version_too_old() {
  # Returns 0 (success) if version $2 is below minimum required for OCP $1 (should remove).
  # Returns 1 (failure) if version $2 meets or exceeds minimum (should keep).
  # Note: Return logic follows shell idiom (0=true/success, 1=false/failure).
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
    if is_version_too_old "${ocp_version}" "${channel#*\-}"; then
      echo "  - Pruning channel: ${channel}"
      CHANNEL="$channel" yq -i '.entries |= del(.[] | select(.schema == "olm.channel" and .name == env(CHANNEL)))' "catalog-template-${ocp_version//./-}.yaml"
    fi
  done

  # Prune bundles from channels
  for channel in $(yq -r '.entries[] | select(.schema == "olm.channel").name' "catalog-template-${ocp_version//./-}.yaml"); do
    for entry in $(CHANNEL="$channel" yq -r '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL)).entries[].name' "catalog-template-${ocp_version//./-}.yaml"); do
      version=${entry#*\.v}
      if is_version_too_old "${ocp_version}" "${version}"; then
        echo "  - Pruning entry from channel ${channel}: ${entry}"
        CHANNEL="$channel" ENTRY="$entry" yq -i '.entries[] |= (select(.schema == "olm.channel" and .name == env(CHANNEL)).entries |= del(.[] | select(.name == env(ENTRY))))' "catalog-template-${ocp_version//./-}.yaml"
      fi
    done
  done

  # Get all referenced bundle images
  referenced_bundle_images=$(yq -r '.entries[] | select(.schema == "olm.channel") | .entries[].name' "catalog-template-${ocp_version//./-}.yaml" | sort -u)

  # Prune unreferenced bundles
  for bundle_image in $(yq -r '.entries[] | select(.schema == "olm.bundle").image' "catalog-template-${ocp_version//./-}.yaml"); do
    bundle_name_in_template=$(BUNDLE_IMAGE="$bundle_image" yq -r '.entries[] | select(.schema == "olm.bundle" and .image == env(BUNDLE_IMAGE)).name' "catalog-template-${ocp_version//./-}.yaml")
    if ! echo "${referenced_bundle_images}" | grep -q "${bundle_name_in_template}"; then
      echo "  - Pruning unreferenced bundle: ${bundle_name_in_template}"
      BUNDLE_IMAGE="$bundle_image" yq -i '.entries |= del(.[] | select(.schema == "olm.bundle" and .image == env(BUNDLE_IMAGE)))' "catalog-template-${ocp_version//./-}.yaml"
    fi
  done

  # Handle replaces field
  for channel in $(yq -r '.entries[] | select(.schema == "olm.channel").name' "catalog-template-${ocp_version//./-}.yaml"); do
    channel_entries=$(CHANNEL="$channel" yq -r '.entries[] | select(.schema == "olm.channel" and .name == env(CHANNEL)).entries | length' "catalog-template-${ocp_version//./-}.yaml")
    if [[ "${channel_entries}" == "1" ]]; then
      echo "  - Channel ${channel} has only one bundle, removing the 'replaces' field."
      CHANNEL="$channel" yq -i '.entries[] |= (select(.schema == "olm.channel" and .name == env(CHANNEL)).entries[0] |= del(.replaces))' "catalog-template-${ocp_version//./-}.yaml"
    fi
  done
done
