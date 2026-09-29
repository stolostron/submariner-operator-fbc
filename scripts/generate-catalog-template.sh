#! /bin/bash

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -f drop-versions.json && -f catalog-template.yaml ]] || { echo "Missing catalog inputs" >&2; exit 1; }
jq -e 'type == "object" and length > 0 and all(to_entries[]; (.key | test("^[1-9][0-9]*\\.(0|[1-9][0-9]*)$")) and (.value | test("^[0-9]+\\.[0-9]+$")))' drop-versions.json >/dev/null

echo "This script generates OCP-version-specific catalog templates by filtering"
echo "the base catalog-template.yaml to include only Submariner versions that support"
echo "each OCP version (configured in drop-versions.json)."
echo
echo "Using drop version Submariner map:"
jq '.' drop-versions.json

ocp_versions=$(jq -r 'keys[]' drop-versions.json)

is_version_too_old() {
  # The map drops an entire Y-stream, including patch numbers above 99.
  local cutoff candidate_major candidate_minor cutoff_major cutoff_minor
  cutoff=$(jq -r --arg ocp "$1" '.[$ocp]' drop-versions.json)
  [[ "$2" =~ ^([0-9]+)\.([0-9]+)([.+-].*)?$ ]] || return 1
  candidate_major=${BASH_REMATCH[1]}
  candidate_minor=${BASH_REMATCH[2]}
  cutoff_major=${cutoff%%.*}
  cutoff_minor=${cutoff#*.}
  ((10#$candidate_major < 10#$cutoff_major ||
    (10#$candidate_major == 10#$cutoff_major && 10#$candidate_minor <= 10#$cutoff_minor)))
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
    if ! echo "${referenced_bundle_images}" | grep -Fxq "${bundle_name_in_template}"; then
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

# Fail before rendering if the cutoff removes the default channel or all bundles.
for ocp_version in ${ocp_versions}; do
  template="catalog-template-${ocp_version//./-}.yaml"
  default_channel=$(yq -r '.entries[] | select(.schema == "olm.package").defaultChannel' "$template")
  DEFAULT_CHANNEL="$default_channel" yq -e '.entries[] | select(.schema == "olm.channel" and .name == strenv(DEFAULT_CHANNEL)) | .entries | length > 0' "$template" >/dev/null || {
    echo "OCP $ocp_version has no populated default channel after pruning; check the cutoff and available bundles" >&2
    exit 1
  }
done
